import os
import Foundation
import FluidAudio

public final class SileroVADProcessor: @unchecked Sendable {
    public var onChunk: (@Sendable (AudioChunk) -> Void)?
    public var onPreviewChunk: (@Sendable (AudioChunk) -> Void)?

    let configuration: Configuration
    private let core: SileroVADCore
    private let queueLock = NSLock()
    private var processingTail: Task<Void, Never>?

    init(configuration: Configuration = .defaultCandidate) {
        self.configuration = configuration
        self.core = SileroVADCore(configuration: configuration)
    }

    public func process(samples: [Float]) {
        enqueue { [core] in
            await core.process(samples: samples)
        }
    }

    public func flushPending() async -> AudioChunk? {
        await currentProcessingTail()?.value
        return await core.flushPending()
    }

    public func reset() {
        enqueue { [core] in
            await core.reset()
            return SileroVADEmission()
        }
    }

    private func enqueue(_ operation: @escaping @Sendable () async -> SileroVADEmission) {
        queueLock.lock()
        let previous = processingTail
        let task = Task { [weak self] in
            await previous?.value
            let emission = await operation()
            self?.publish(emission)
        }
        processingTail = task
        queueLock.unlock()
    }

    private func currentProcessingTail() -> Task<Void, Never>? {
        queueLock.lock()
        let tail = processingTail
        queueLock.unlock()
        return tail
    }

    private func publish(_ emission: SileroVADEmission) {
        for preview in emission.previewChunks {
            DispatchQueue.main.async { [weak self] in
                self?.onPreviewChunk?(preview)
            }
        }
        for chunk in emission.finalChunks {
            DispatchQueue.main.async { [weak self] in
                self?.onChunk?(chunk)
            }
        }
    }

    struct Configuration: Sendable {
        static let modelFileName = "silero-vad-unified-256ms-v6.0.0.mlmodelc"

        let threshold: Float
        let minSpeechDuration: TimeInterval
        let minSilenceDuration: TimeInterval
        let maxSpeechDuration: TimeInterval
        let speechPadding: TimeInterval
        let modelDirectory: URL
        let mergeGapSeconds: TimeInterval
        let mergeMaxSeconds: TimeInterval

        static let defaultCandidate = Configuration(
            threshold: 0.6,
            minSpeechDuration: 0.25,
            minSilenceDuration: 0.4,
            maxSpeechDuration: 14.0,
            speechPadding: 0.12,
            modelDirectory: Configuration.defaultModelDirectory,
            mergeGapSeconds: 1.1,
            mergeMaxSeconds: VADProcessor.maxChunkDuration
        )

        /// 모델은 재시작 후에도 유지돼야 하므로 temp가 아니라 Application Support에 둔다.
        /// 벤치마크는 MINTO_FLUIDAUDIO_MODEL_DIR 환경변수로 자체 경로를 쓴다.
        static var defaultModelDirectory: URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            return base
                .appendingPathComponent("Minto", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("fluidaudio", isDirectory: true)
        }

        init(
            threshold: Float,
            minSpeechDuration: TimeInterval,
            minSilenceDuration: TimeInterval,
            maxSpeechDuration: TimeInterval,
            speechPadding: TimeInterval,
            modelDirectory: URL,
            mergeGapSeconds: TimeInterval,
            mergeMaxSeconds: TimeInterval
        ) {
            self.threshold = threshold
            self.minSpeechDuration = minSpeechDuration
            self.minSilenceDuration = minSilenceDuration
            self.maxSpeechDuration = maxSpeechDuration
            self.speechPadding = speechPadding
            self.modelDirectory = modelDirectory
            self.mergeGapSeconds = mergeGapSeconds
            self.mergeMaxSeconds = mergeMaxSeconds
        }

        init?(environment: [String: String]) {
            let defaults = Self.defaultCandidate
            let modelDirectory = Self.modelDirectory(environment: environment) ?? defaults.modelDirectory
            self.init(
                threshold: Self.float(environment["MINTO_SILERO_VAD_THRESHOLD"]) ?? defaults.threshold,
                minSpeechDuration: Self.double(environment["MINTO_SILERO_MIN_SPEECH_SEC"]) ?? defaults.minSpeechDuration,
                minSilenceDuration: Self.double(environment["MINTO_SILERO_MIN_SILENCE_SEC"]) ?? defaults.minSilenceDuration,
                maxSpeechDuration: Self.double(environment["MINTO_SILERO_MAX_SPEECH_SEC"]) ?? defaults.maxSpeechDuration,
                speechPadding: Self.double(environment["MINTO_SILERO_SPEECH_PADDING_SEC"]) ?? defaults.speechPadding,
                modelDirectory: modelDirectory,
                mergeGapSeconds: Self.double(environment["MINTO_VAD_MERGE_GAP_SEC"]) ?? defaults.mergeGapSeconds,
                mergeMaxSeconds: Self.double(environment["MINTO_VAD_MERGE_MAX_SEC"]) ?? defaults.mergeMaxSeconds
            )
        }

        var hasLocalModelBundle: Bool {
            Self.modelBundleCandidates(in: modelDirectory).contains { url in
                FileManager.default.fileExists(atPath: url.path)
            }
        }

        var segmentationConfig: VadSegmentationConfig {
            var config = VadSegmentationConfig.default
            config.minSpeechDuration = minSpeechDuration
            config.minSilenceDuration = minSilenceDuration
            config.maxSpeechDuration = maxSpeechDuration
            config.speechPadding = speechPadding
            return config
        }

        private static func modelDirectory(environment: [String: String]) -> URL? {
            let value = environment["MINTO_FLUIDAUDIO_MODEL_DIR"] ?? environment["FLUIDAUDIO_MODEL_DIR"]
            guard let path = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        private static func modelBundleCandidates(in directory: URL) -> [URL] {
            [
                directory
                    .appendingPathComponent("Models", isDirectory: true)
                    .appendingPathComponent("silero-vad", isDirectory: true)
                    .appendingPathComponent(modelFileName, isDirectory: true),
                directory
                    .appendingPathComponent("Models", isDirectory: true)
                    .appendingPathComponent("silero-vad-coreml", isDirectory: true)
                    .appendingPathComponent(modelFileName, isDirectory: true),
            ]
        }

        private static func double(_ value: String?) -> Double? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let parsed = Double(value),
                  parsed >= 0 else {
                return nil
            }
            return parsed
        }

        private static func float(_ value: String?) -> Float? {
            double(value).map(Float.init)
        }
    }
}

extension SileroVADProcessor: VoiceActivityDetector {}

private struct SileroVADEmission: Sendable {
    var finalChunks: [AudioChunk] = []
    var previewChunks: [AudioChunk] = []
}

/// 임의 크기로 들어오는 오디오를 모델 프레임 크기(4096샘플) 단위로 잘라 내보낸다.
/// 잔여(<프레임)는 다음 append까지 보관한다.
struct SileroModelFrameAccumulator {
    private let frameSize: Int
    private var pending: [Float] = []

    init(frameSize: Int) {
        self.frameSize = max(1, frameSize)
    }

    var pendingCount: Int { pending.count }

    mutating func append(_ samples: [Float]) -> [[Float]] {
        pending.append(contentsOf: samples)
        guard pending.count >= frameSize else { return [] }
        var frames: [[Float]] = []
        var offset = 0
        while pending.count - offset >= frameSize {
            frames.append(Array(pending[offset..<(offset + frameSize)]))
            offset += frameSize
        }
        pending.removeFirst(offset)
        return frames
    }

    mutating func reset() {
        pending = []
    }
}

private actor SileroVADCore {
    private static let sampleRate = 16_000
    private static let minSpeechSamples = Int(VADProcessor.minSpeechDuration * Double(sampleRate))
    private static let previewIntervalSamples = sampleRate
    private static let maxPreviewSamples = 8 * sampleRate
    private static let inactiveRetentionSamples = 5 * sampleRate

    private let configuration: SileroVADProcessor.Configuration
    private var manager: VadManager?
    private var streamState = VadStreamState.initial()
    private var sampleBuffer: [Float] = []
    private var bufferStartSample = 0
    private var activeStartSample: Int?
    private var pendingFinalRange: Range<Int>?
    private var lastPreviewEndSample = 0
    /// Silero 모델은 정확히 4096샘플(256ms) 프레임을 기대한다. FluidAudio는 모자란 입력을
    /// 마지막 샘플 반복으로 패딩하는데, 라이브 마이크 버퍼(~85ms)를 그대로 넘기면 매 프레임의
    /// 2/3가 패딩이 되어 음성 확률이 희석돼 speechStart가 영원히 발생하지 않는다.
    /// 그래서 들어온 샘플을 여기 모았다가 정확히 프레임 단위로만 모델에 보낸다.
    private var frameAccumulator = SileroModelFrameAccumulator(frameSize: VadManager.chunkSize)

    init(configuration: SileroVADProcessor.Configuration) {
        self.configuration = configuration
    }

    func process(samples: [Float]) async -> SileroVADEmission {
        guard !samples.isEmpty else { return SileroVADEmission() }
        sampleBuffer.append(contentsOf: samples)

        var emission = SileroVADEmission()
        for frame in frameAccumulator.append(samples) {
            guard await processFrame(frame, into: &emission) else { break }
        }
        return emission
    }

    private func processFrame(_ frame: [Float], into emission: inout SileroVADEmission) async -> Bool {
        do {
            let manager = try await loadManager()
            let result = try await manager.processStreamingChunk(
                frame,
                state: streamState,
                config: configuration.segmentationConfig
            )
            streamState = result.state
            let frameEmission = handle(result: result)
            emission.finalChunks.append(contentsOf: frameEmission.finalChunks)
            emission.previewChunks.append(contentsOf: frameEmission.previewChunks)
            return true
        } catch {
            Log.vad.error("Silero processing failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func flushPending() -> AudioChunk? {
        if let range = pendingFinalRange {
            pendingFinalRange = nil
            let chunk = makeChunk(startSample: range.lowerBound, endSample: range.upperBound, trailingSilence: 0, isPreview: false)
            trimBuffer(keepingFrom: range.upperBound)
            return chunk
        }

        guard let start = activeStartSample else {
            trimBuffer(keepingFrom: streamState.processedSamples)
            return nil
        }
        // 발화가 진행 중이면 모델이 아직 못 본 프레임 미만 잔여(<256ms)도 마지막 발화에 포함한다.
        let bufferEnd = bufferStartSample + sampleBuffer.count
        let end = max(streamState.processedSamples, bufferEnd)
        let chunk = makeChunk(startSample: start, endSample: end, trailingSilence: 0, isPreview: false)
        activeStartSample = nil
        if let chunk {
            let endSeconds = chunk.endSeconds ?? Double(end) / Double(Self.sampleRate)
            trimBuffer(keepingFrom: Int(endSeconds * Double(Self.sampleRate)))
        }
        return chunk
    }

    func reset() async {
        if let manager {
            streamState = await manager.makeStreamState()
        } else {
            streamState = .initial()
        }
        sampleBuffer = []
        bufferStartSample = 0
        frameAccumulator.reset()
        activeStartSample = nil
        pendingFinalRange = nil
        lastPreviewEndSample = 0
    }

    private func loadManager() async throws -> VadManager {
        if let manager { return manager }
        let manager = try await VadManager(
            config: VadConfig(defaultThreshold: configuration.threshold),
            modelDirectory: configuration.modelDirectory
        )
        self.manager = manager
        streamState = await manager.makeStreamState()
        return manager
    }

    private func handle(result: VadStreamResult) -> SileroVADEmission {
        var emission = SileroVADEmission()

        if let event = result.event {
            switch event.kind {
            case .speechStart:
                if let pending = pendingFinalRange {
                    let gapSamples = event.sampleIndex - pending.upperBound
                    let maxGapSamples = Int(configuration.mergeGapSeconds * Double(Self.sampleRate))
                    let maxMergedSamples = Int(configuration.mergeMaxSeconds * Double(Self.sampleRate))
                    if gapSamples >= 0,
                       gapSamples <= maxGapSamples,
                       event.sampleIndex - pending.lowerBound <= maxMergedSamples {
                        activeStartSample = pending.lowerBound
                        pendingFinalRange = nil
                    } else {
                        emitPendingFinal(into: &emission)
                        activeStartSample = event.sampleIndex
                    }
                } else {
                    activeStartSample = event.sampleIndex
                }
            case .speechEnd:
                if let start = activeStartSample {
                    pendingFinalRange = start..<event.sampleIndex
                }
                activeStartSample = nil
            }
        }

        while let start = activeStartSample,
              streamState.processedSamples - start >= Int(configuration.mergeMaxSeconds * Double(Self.sampleRate)) {
            let end = start + Int(configuration.mergeMaxSeconds * Double(Self.sampleRate))
            if let chunk = makeChunk(startSample: start, endSample: end, trailingSilence: 0, isPreview: false) {
                emission.finalChunks.append(chunk)
            }
            activeStartSample = end
            trimBuffer(keepingFrom: end)
        }

        if let pending = pendingFinalRange {
            let maxGapSamples = Int(configuration.mergeGapSeconds * Double(Self.sampleRate))
            if streamState.processedSamples - pending.upperBound >= maxGapSamples {
                emitPendingFinal(into: &emission)
            }
        }

        if let preview = makePreviewIfNeeded() {
            emission.previewChunks.append(preview)
        }
        if activeStartSample == nil, pendingFinalRange == nil {
            trimBuffer(keepingFrom: streamState.processedSamples - Self.inactiveRetentionSamples)
        }
        return emission
    }

    private func emitPendingFinal(into emission: inout SileroVADEmission) {
        guard let pending = pendingFinalRange else { return }
        if let chunk = makeChunk(
            startSample: pending.lowerBound,
            endSample: pending.upperBound,
            trailingSilence: configuration.minSilenceDuration,
            isPreview: false
        ) {
            emission.finalChunks.append(chunk)
        }
        pendingFinalRange = nil
        trimBuffer(keepingFrom: pending.upperBound)
    }

    private func makePreviewIfNeeded() -> AudioChunk? {
        guard let start = activeStartSample else { return nil }
        let end = streamState.processedSamples
        guard end - start >= Self.minSpeechSamples else { return nil }
        guard end - lastPreviewEndSample >= Self.previewIntervalSamples else { return nil }
        lastPreviewEndSample = end
        let previewStart = max(start, end - Self.maxPreviewSamples)
        return makeChunk(startSample: previewStart, endSample: end, trailingSilence: 0, isPreview: true)
    }

    private func makeChunk(
        startSample: Int,
        endSample: Int,
        trailingSilence: TimeInterval,
        isPreview: Bool
    ) -> AudioChunk? {
        let start = max(startSample, bufferStartSample)
        let end = min(endSample, bufferStartSample + sampleBuffer.count)
        guard end > start, end - start >= Self.minSpeechSamples else { return nil }

        let startIndex = start - bufferStartSample
        let endIndex = end - bufferStartSample
        let samples = Array(sampleBuffer[startIndex..<endIndex])
        return AudioChunk(
            samples: samples,
            durationSeconds: Double(samples.count) / Double(Self.sampleRate),
            trailingSilence: trailingSilence,
            isPreview: isPreview,
            startSeconds: Double(start) / Double(Self.sampleRate),
            endSeconds: Double(end) / Double(Self.sampleRate)
        )
    }

    private func trimBuffer(keepingFrom sample: Int) {
        let keepFrom = max(bufferStartSample, sample)
        let dropCount = min(sampleBuffer.count, max(0, keepFrom - bufferStartSample))
        guard dropCount > 0 else { return }
        sampleBuffer.removeFirst(dropCount)
        bufferStartSample += dropCount
    }
}
