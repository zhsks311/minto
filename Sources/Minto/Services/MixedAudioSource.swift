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
        lock.unlock()

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
        for mixedSamples in mixer.append(samples, source: source) {
            onBuffer?(mixedSamples)
            onLevel?(STTAudioUtilities.normalizedLevel(mixedSamples))
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
}

enum MixedAudioInputSource: Sendable {
    case microphone
    case systemAudio
}

final class DualAudioBufferMixer: @unchecked Sendable {
    private static let defaultMaxBufferedSamples = Int(STTAudioUtilities.sampleRate / 4)

    private let lock = NSLock()
    private let gain: Float
    private let maxBufferedSamples: Int
    private var microphoneSamples: [Float] = []
    private var systemAudioSamples: [Float] = []

    init(gain: Float = 0.5, maxBufferedSamples: Int = DualAudioBufferMixer.defaultMaxBufferedSamples) {
        self.gain = gain
        self.maxBufferedSamples = max(1, maxBufferedSamples)
    }

    func append(_ samples: [Float], source: MixedAudioInputSource) -> [[Float]] {
        guard !samples.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        switch source {
        case .microphone:
            microphoneSamples.append(contentsOf: samples)
        case .systemAudio:
            systemAudioSamples.append(contentsOf: samples)
        }

        var outputBuffers: [[Float]] = []
        let frameCount = min(microphoneSamples.count, systemAudioSamples.count)
        if frameCount > 0 {
            let mixed = Self.mix(
                microphone: Array(microphoneSamples.prefix(frameCount)),
                systemAudio: Array(systemAudioSamples.prefix(frameCount)),
                gain: gain
            )
            microphoneSamples.removeFirst(frameCount)
            systemAudioSamples.removeFirst(frameCount)
            outputBuffers.append(mixed)
        }

        outputBuffers.append(contentsOf: overflowBuffers())
        return outputBuffers
    }

    private func overflowBuffers() -> [[Float]] {
        var outputBuffers: [[Float]] = []
        if microphoneSamples.count > maxBufferedSamples {
            let overflowCount = microphoneSamples.count - maxBufferedSamples
            outputBuffers.append(Self.passthrough(Array(microphoneSamples.prefix(overflowCount))))
            microphoneSamples.removeFirst(overflowCount)
        }
        if systemAudioSamples.count > maxBufferedSamples {
            let overflowCount = systemAudioSamples.count - maxBufferedSamples
            outputBuffers.append(Self.passthrough(Array(systemAudioSamples.prefix(overflowCount))))
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
}
