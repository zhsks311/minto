import Foundation

public final class VADProcessor: @unchecked Sendable {

    // MARK: - Constants

    public static let silenceDurationThreshold: TimeInterval = 1.5
    public static let maxChunkDuration: TimeInterval = 15.0
    public static let sampleRate: Double = 16000
    public static let minSpeechDuration: TimeInterval = 0.5

    private static let maxSamples: Int = Int(maxChunkDuration * sampleRate)
    private static let minSpeechSamples: Int = Int(minSpeechDuration * sampleRate)
    private static let silenceSampleThreshold: Int = Int(silenceDurationThreshold * sampleRate)

    private static let noiseOffsetDB: Float = 10.0
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

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    public func process(samples: [Float]) {
        queue.async { [weak self] in
            self?.processInternal(samples: samples)
        }
    }

    // MARK: - Private

    private func processInternal(samples: [Float]) {
        let energyDB = computeEnergyDB(samples: samples)

        if isCalibrating {
            if energyDB.isFinite {
                calibrationEnergies.append(energyDB)
            }
            if calibrationEnergies.count >= VADProcessor.calibrationFrameCount {
                let noiseFloor = calibrationEnergies.reduce(0, +) / Float(calibrationEnergies.count)
                adaptiveThresholdDB = noiseFloor + VADProcessor.noiseOffsetDB
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
                flushChunk(trailingSilence: trailingSilence)
            }
        } else {
            silenceSampleCount = 0
            buffer.append(contentsOf: samples)
            if buffer.count >= VADProcessor.maxSamples {
                flushChunk(trailingSilence: 0)
            } else if buffer.count >= VADProcessor.minPreviewSamples {
                let now = Date()
                if now.timeIntervalSince(lastPreviewTime) >= VADProcessor.previewInterval {
                    lastPreviewTime = now
                    let previewSamples = buffer.count > VADProcessor.maxPreviewWindowSamples
                        ? Array(buffer.suffix(VADProcessor.maxPreviewWindowSamples))
                        : buffer
                    let dur = Double(previewSamples.count) / VADProcessor.sampleRate
                    let chunk = AudioChunk(samples: previewSamples, durationSeconds: dur,
                                          trailingSilence: 0, isPreview: true)
                    DispatchQueue.main.async { [weak self] in
                        self?.onPreviewChunk?(chunk)
                    }
                }
            }
        }
    }

    private func flushChunk(trailingSilence: TimeInterval) {
        fputs("[VAD] flushChunk samples=\(buffer.count) minRequired=\(VADProcessor.minSpeechSamples)\n", stderr)
        guard buffer.count >= VADProcessor.minSpeechSamples else {
            buffer = []
            silenceSampleCount = 0
            return
        }

        let samples = buffer
        let durationSeconds = Double(samples.count) / VADProcessor.sampleRate
        let chunk = AudioChunk(
            samples: samples,
            durationSeconds: durationSeconds,
            trailingSilence: trailingSilence
        )

        buffer = []
        silenceSampleCount = 0
        lastPreviewTime = .distantPast

        DispatchQueue.main.async { [weak self] in
            self?.onChunk?(chunk)
        }
    }

    private func computeEnergyDB(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -.infinity }
        let sumOfSquares = samples.reduce(0.0 as Float) { $0 + $1 * $1 }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        guard rms > 0 else { return -.infinity }
        return 20 * log10(rms)
    }
}
