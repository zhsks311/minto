import Foundation

public final class MixedAudioSource: AudioSourceProtocol, @unchecked Sendable {
    public var onBuffer: (@Sendable ([Float]) -> Void)?
    public var onError: (@Sendable (AudioSourceError) -> Void)?
    public var onLevel: (@Sendable (Float) -> Void)?

    public var availableDevices: [AudioDevice] {
        microphone.availableDevices + systemAudio.availableDevices
    }

    private let microphone: any AudioSourceProtocol
    private let systemAudio: any AudioSourceProtocol
    private let mixer: DualAudioBufferMixer
    private let lock = NSLock()
    private var isRunning = false
    private var emittedMixedSamples = 0
    private var channelActivityTimeline: [ChannelActivityEntry] = []

    public convenience init() {
        self.init(microphone: MicrophoneSource(), systemAudio: SystemAudioSource())
    }

    init(
        microphone: any AudioSourceProtocol,
        systemAudio: any AudioSourceProtocol,
        mixer: DualAudioBufferMixer = DualAudioBufferMixer()
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.mixer = mixer
        wireChildSources()
    }

    public func start() throws {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        emittedMixedSamples = 0
        channelActivityTimeline.removeAll(keepingCapacity: true)
        lock.unlock()

        mixer.reset()
        do {
            try microphone.start()
            try systemAudio.start()
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        lock.lock()
        let wasRunning = isRunning
        isRunning = false
        lock.unlock()

        microphone.stop()
        systemAudio.stop()

        guard wasRunning else { return }
        mixer.reset()
    }

    public func selectDevice(_ device: AudioDevice) throws {
        if microphone.availableDevices.contains(device) {
            try microphone.selectDevice(device)
            return
        }
        if systemAudio.availableDevices.contains(device) {
            try systemAudio.selectDevice(device)
            return
        }
        throw AudioSourceError.deviceNotFound(device)
    }

    private func wireChildSources() {
        microphone.onBuffer = { [weak self] samples in
            self?.handleBuffer(samples, source: .microphone)
        }
        systemAudio.onBuffer = { [weak self] samples in
            self?.handleBuffer(samples, source: .systemAudio)
        }
        microphone.onError = { [weak self] error in
            self?.onError?(error)
        }
        systemAudio.onError = { [weak self] error in
            self?.onError?(error)
        }
        microphone.onLevel = { [weak self] level in
            self?.handleLevel(level)
        }
        systemAudio.onLevel = { [weak self] level in
            self?.handleLevel(level)
        }
    }

    private func handleBuffer(_ samples: [Float], source: MixedAudioInputSource) {
        guard isRunningSnapshot() else { return }
        for chunk in mixer.append(samples, source: source) {
            recordChannelActivity(for: chunk)
            onBuffer?(chunk.samples)
            onLevel?(STTAudioUtilities.normalizedLevel(chunk.samples))
        }
    }

    private func handleLevel(_ level: Float) {
        guard isRunningSnapshot() else { return }
        onLevel?(level)
    }

    private func isRunningSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    private func recordChannelActivity(for chunk: MixedChunk) {
        guard !chunk.samples.isEmpty else { return }

        // This offset is the same mixed sample clock delivered to VAD via onBuffer.
        // Mic/system capture timestamps are not synchronized here; channel labels only
        // mean "which aligned input had more energy in this mixed timeline interval."
        lock.lock()
        let startSample = emittedMixedSamples
        let endSample = startSample + chunk.samples.count
        emittedMixedSamples = endSample
        channelActivityTimeline.append(ChannelActivityEntry(
            startSample: startSample,
            endSample: endSample,
            dominant: chunk.dominant
        ))
        pruneChannelActivityTimeline()
        lock.unlock()
    }

    private func pruneChannelActivityTimeline() {
        let minRetainedSample = max(0, emittedMixedSamples - Self.maxChannelActivityRetentionSamples)
        channelActivityTimeline.removeAll { $0.endSample <= minRetainedSample }
        if channelActivityTimeline.count > Self.maxChannelActivityEntries {
            channelActivityTimeline.removeFirst(channelActivityTimeline.count - Self.maxChannelActivityEntries)
        }
    }

    // Final chunk labeling happens shortly after emission. Ten minutes and 20k entries
    // leave headroom for slow local STT while bounding runaway long-session memory.
    private static let maxChannelActivityRetentionSeconds: Double = 600
    private static let maxChannelActivityRetentionSamples = Int(
        maxChannelActivityRetentionSeconds * STTAudioUtilities.sampleRate
    )
    private static let maxChannelActivityEntries = 20_000
}

extension MixedAudioSource: RecordingChannelActivityProviding {
    func dominantChannel(startSeconds: Double, endSeconds: Double) -> MixedAudioInputSource? {
        guard endSeconds > startSeconds else { return nil }

        let startSample = max(0, Int((startSeconds * STTAudioUtilities.sampleRate).rounded(.down)))
        let endSample = max(startSample, Int((endSeconds * STTAudioUtilities.sampleRate).rounded(.up)))
        guard endSample > startSample else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var microphoneSamples = 0
        var systemAudioSamples = 0
        for entry in channelActivityTimeline where entry.endSample > startSample && entry.startSample < endSample {
            guard let dominant = entry.dominant else { continue }
            let overlap = min(entry.endSample, endSample) - max(entry.startSample, startSample)
            guard overlap > 0 else { continue }
            switch dominant {
            case .microphone:
                microphoneSamples += overlap
            case .systemAudio:
                systemAudioSamples += overlap
            }
        }

        if microphoneSamples > systemAudioSamples {
            return .microphone
        }
        if systemAudioSamples > microphoneSamples {
            return .systemAudio
        }
        return nil
    }

    func resetChannelActivity() {
        lock.lock()
        emittedMixedSamples = 0
        channelActivityTimeline.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

protocol RecordingChannelActivityProviding: AnyObject {
    func dominantChannel(startSeconds: Double, endSeconds: Double) -> MixedAudioInputSource?
    func resetChannelActivity()
}

enum MixedAudioInputSource: Sendable, Equatable {
    case microphone
    case systemAudio
}

struct MixedChunk: Sendable, Equatable {
    let samples: [Float]
    let dominant: MixedAudioInputSource?
}

private struct ChannelActivityEntry: Sendable {
    let startSample: Int
    let endSample: Int
    let dominant: MixedAudioInputSource?
}

final class DualAudioBufferMixer: @unchecked Sendable {
    private static let defaultMaxBufferedSamples = Int(STTAudioUtilities.sampleRate / 4)
    // Treat lower RMS values as silence. The dominance ratio intentionally leaves
    // similar-energy overlap unlabeled because a missing label is safer than a wrong one.
    private static let silenceRMS: Float = 0.0001
    private static let dominanceRatio: Float = 1.5

    private let lock = NSLock()
    private let gain: Float
    private let maxBufferedSamples: Int
    private var microphoneSamples: [Float] = []
    private var systemAudioSamples: [Float] = []

    init(gain: Float = 0.5, maxBufferedSamples: Int = DualAudioBufferMixer.defaultMaxBufferedSamples) {
        self.gain = gain
        self.maxBufferedSamples = max(1, maxBufferedSamples)
    }

    func append(_ samples: [Float], source: MixedAudioInputSource) -> [MixedChunk] {
        guard !samples.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        switch source {
        case .microphone:
            microphoneSamples.append(contentsOf: samples)
        case .systemAudio:
            systemAudioSamples.append(contentsOf: samples)
        }

        var outputBuffers: [MixedChunk] = []
        let frameCount = min(microphoneSamples.count, systemAudioSamples.count)
        if frameCount > 0 {
            let microphoneFrames = Array(microphoneSamples.prefix(frameCount))
            let systemAudioFrames = Array(systemAudioSamples.prefix(frameCount))
            let mixed = Self.mix(
                microphone: microphoneFrames,
                systemAudio: systemAudioFrames,
                gain: gain
            )
            microphoneSamples.removeFirst(frameCount)
            systemAudioSamples.removeFirst(frameCount)
            outputBuffers.append(MixedChunk(
                samples: mixed,
                dominant: Self.dominantChannel(microphone: microphoneFrames, systemAudio: systemAudioFrames)
            ))
        }

        outputBuffers.append(contentsOf: overflowBuffers())
        return outputBuffers
    }

    private func overflowBuffers() -> [MixedChunk] {
        var outputBuffers: [MixedChunk] = []
        if microphoneSamples.count > maxBufferedSamples {
            let overflowCount = microphoneSamples.count - maxBufferedSamples
            outputBuffers.append(MixedChunk(
                samples: Self.passthrough(Array(microphoneSamples.prefix(overflowCount))),
                dominant: .microphone
            ))
            microphoneSamples.removeFirst(overflowCount)
        }
        if systemAudioSamples.count > maxBufferedSamples {
            let overflowCount = systemAudioSamples.count - maxBufferedSamples
            outputBuffers.append(MixedChunk(
                samples: Self.passthrough(Array(systemAudioSamples.prefix(overflowCount))),
                dominant: .systemAudio
            ))
            systemAudioSamples.removeFirst(overflowCount)
        }
        return outputBuffers
    }

    private static func passthrough(_ samples: [Float]) -> [Float] {
        samples.map { max(-1, min(1, $0)) }
    }

    func reset() {
        lock.lock()
        microphoneSamples.removeAll(keepingCapacity: true)
        systemAudioSamples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    static func mix(microphone: [Float], systemAudio: [Float], gain: Float = 0.5) -> [Float] {
        let frameCount = min(microphone.count, systemAudio.count)
        guard frameCount > 0 else { return [] }

        var mixed: [Float] = []
        mixed.reserveCapacity(frameCount)
        for index in 0..<frameCount {
            let sample = microphone[index] * gain + systemAudio[index] * gain
            mixed.append(max(-1, min(1, sample)))
        }
        return mixed
    }

    private static func dominantChannel(
        microphone: [Float],
        systemAudio: [Float]
    ) -> MixedAudioInputSource? {
        let microphoneRMS = rms(microphone)
        let systemAudioRMS = rms(systemAudio)
        guard microphoneRMS > silenceRMS || systemAudioRMS > silenceRMS else {
            return nil
        }
        if microphoneRMS >= systemAudioRMS * dominanceRatio {
            return .microphone
        }
        if systemAudioRMS >= microphoneRMS * dominanceRatio {
            return .systemAudio
        }
        return nil
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0.0 as Float) { $0 + $1 * $1 }
        return (sumOfSquares / Float(samples.count)).squareRoot()
    }
}
