import Foundation

public final class VADProcessor: @unchecked Sendable {

    // MARK: - Constants

    public static let silenceDurationThreshold: TimeInterval = 1.5
    public static let maxChunkDuration: TimeInterval = 15.0
    /// ramp-up: 녹음 시작 직후 첫 청크는 더 짧게 끊어 초반 응답 지연을 줄인다.
    public static let firstChunkMaxDuration: TimeInterval = 5.0
    public static let sampleRate: Double = 16000
    public static let minSpeechDuration: TimeInterval = 0.5

    private static let maxSamples: Int = Int(maxChunkDuration * sampleRate)
    private static let firstChunkMaxSamples: Int = Int(firstChunkMaxDuration * sampleRate)
    private static let minSpeechSamples: Int = Int(minSpeechDuration * sampleRate)
    private static let silenceSampleThreshold: Int = Int(silenceDurationThreshold * sampleRate)

    private static let calibrationFrameCount: Int = 10

    // MARK: - Public callbacks

    public var onChunk: (@Sendable (AudioChunk) -> Void)?
    /// 말하는 도중 previewInterval마다 현재 버퍼를 미리 전달하는 콜백 (pendingSegment 갱신용)
    public var onPreviewChunk: (@Sendable (AudioChunk) -> Void)?

    private static let previewInterval: TimeInterval = 1.0
    private static let minPreviewSamples: Int = Int(0.5 * sampleRate)
    // preview는 최근 8초만 전달 — 버퍼가 길어져도 STT 처리 시간이 일정하게 유지됨
    private static let maxPreviewWindowSamples: Int = Int(8.0 * sampleRate)

    // MARK: - Private state (accessed only on queue)

    private var buffer: [Float] = []
    private var silenceSampleCount: Int = 0
    private let queue = DispatchQueue(label: "minto.vad", qos: .userInitiated)

    private var calibrationEnergies: [Float] = []
    private var isCalibrating = true
    private var adaptiveThresholdDB: Float = -40
    private var lastPreviewTime: Date = .distantPast
    /// 이번 녹음에서 방출한 청크 수 — 0이면 ramp-up(짧은 첫 청크) 적용
    private var emittedChunkCount: Int = 0
    private var processedSampleCount: Int = 0
    private var bufferStartSample: Int?
    private let noiseOffsetDB: Float

    // MARK: - Init

    public init(noiseOffsetDB: Float = 10.0) {
        self.noiseOffsetDB = noiseOffsetDB
    }

    // MARK: - Public API

    public func process(samples: [Float]) {
        queue.async { [weak self] in
            self?.processInternal(samples: samples)
        }
    }

    /// 녹음 종료 시 남아 있는 발화 버퍼를 최종 청크로 꺼낸다.
    /// `onChunk`를 호출하지 않으므로 종료 경로에서 중복 enqueue race 없이 직접 처리할 수 있다.
    public func flushPending() async -> AudioChunk? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: self.drainBufferedChunk(trailingSilence: 0, forced: false))
            }
        }
    }

    /// 새 녹음 시작 시 호출 — 버퍼와 ramp-up 카운터를 초기화한다.
    /// calibration 상태(noise floor)는 의도적으로 보존한다.
    public func reset() {
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer = []
            self.silenceSampleCount = 0
            self.emittedChunkCount = 0
            self.processedSampleCount = 0
            self.bufferStartSample = nil
            self.lastPreviewTime = .distantPast
        }
    }

    // MARK: - Private

    private func processInternal(samples: [Float]) {
        let frameStartSample = processedSampleCount
        defer { processedSampleCount += samples.count }

        let energyDB = computeEnergyDB(samples: samples)

        if isCalibrating {
            if energyDB.isFinite {
                calibrationEnergies.append(energyDB)
            }
            if calibrationEnergies.count >= VADProcessor.calibrationFrameCount {
                let noiseFloor = calibrationEnergies.reduce(0, +) / Float(calibrationEnergies.count)
                adaptiveThresholdDB = noiseFloor + noiseOffsetDB
                isCalibrating = false
                fputs("[VAD] calibrated: noiseFloor=\(noiseFloor)dB threshold=\(adaptiveThresholdDB)dB\n", stderr)
            }
            return
        }

        let isSilent = energyDB < adaptiveThresholdDB

        if isSilent {
            silenceSampleCount += samples.count
            if silenceSampleCount >= VADProcessor.silenceSampleThreshold && !buffer.isEmpty {
                let trailingSilence = Double(silenceSampleCount) / VADProcessor.sampleRate
                flushChunk(trailingSilence: trailingSilence, forced: false)
            }
        } else {
            silenceSampleCount = 0
            if buffer.isEmpty {
                bufferStartSample = frameStartSample
            }
            buffer.append(contentsOf: samples)
            let chunkCap = emittedChunkCount == 0
                ? VADProcessor.firstChunkMaxSamples
                : VADProcessor.maxSamples
            if buffer.count >= chunkCap {
                flushChunk(trailingSilence: 0, forced: true)
            } else if buffer.count >= VADProcessor.minPreviewSamples {
                let now = Date()
                if now.timeIntervalSince(lastPreviewTime) >= VADProcessor.previewInterval {
                    lastPreviewTime = now
                    let previewSamples = buffer.count > VADProcessor.maxPreviewWindowSamples
                        ? Array(buffer.suffix(VADProcessor.maxPreviewWindowSamples))
                        : buffer
                    let previewStartSample = (bufferStartSample ?? frameStartSample) + max(0, buffer.count - previewSamples.count)
                    let previewEndSample = previewStartSample + previewSamples.count
                    let dur = Double(previewSamples.count) / VADProcessor.sampleRate
                    let chunk = AudioChunk(
                        samples: previewSamples,
                        durationSeconds: dur,
                        trailingSilence: 0,
                        isPreview: true,
                        startSeconds: Double(previewStartSample) / VADProcessor.sampleRate,
                        endSeconds: Double(previewEndSample) / VADProcessor.sampleRate
                    )
                    DispatchQueue.main.async { [weak self] in
                        self?.onPreviewChunk?(chunk)
                    }
                }
            }
        }
    }

    private func flushChunk(trailingSilence: TimeInterval, forced: Bool) {
        fputs("[VAD] flushChunk samples=\(buffer.count) minRequired=\(VADProcessor.minSpeechSamples)\n", stderr)
        guard let chunk = drainBufferedChunk(trailingSilence: trailingSilence, forced: forced) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onChunk?(chunk)
        }
    }

    private func drainBufferedChunk(trailingSilence: TimeInterval, forced: Bool) -> AudioChunk? {
        guard buffer.count >= VADProcessor.minSpeechSamples else {
            buffer = []
            silenceSampleCount = 0
            return nil
        }

        let samples = buffer
        let startSample = bufferStartSample ?? max(0, processedSampleCount - samples.count)
        let endSample = startSample + samples.count
        let durationSeconds = Double(samples.count) / VADProcessor.sampleRate
        let chunk = AudioChunk(
            samples: samples,
            durationSeconds: durationSeconds,
            trailingSilence: trailingSilence,
            startSeconds: Double(startSample) / VADProcessor.sampleRate,
            endSeconds: Double(endSample) / VADProcessor.sampleRate
        )

        buffer = []
        bufferStartSample = nil
        silenceSampleCount = 0
        lastPreviewTime = .distantPast
        // ramp-up은 "연속 발화의 첫 강제 분할"을 짧게 하려는 것이므로,
        // 침묵으로 자연 종료된 짧은 청크는 카운터를 소진하지 않는다.
        if forced {
            emittedChunkCount += 1
        }
        return chunk
    }

    private func computeEnergyDB(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -.infinity }
        let sumOfSquares = samples.reduce(0.0 as Float) { $0 + $1 * $1 }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        guard rms > 0 else { return -.infinity }
        return 20 * log10(rms)
    }
}
