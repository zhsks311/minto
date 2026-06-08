import Foundation

struct EmptyFinalRepairPolicy: Sendable, Equatable {
    let isEnabled: Bool
    let padSeconds: Double
    let minChunkSeconds: Double
    let minAudioDB: Float
    let maxBufferedSeconds: Double

    static let disabled = EmptyFinalRepairPolicy(
        isEnabled: false,
        padSeconds: 0,
        minChunkSeconds: 0,
        minAudioDB: -.infinity,
        maxBufferedSeconds: 0
    )

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> EmptyFinalRepairPolicy {
        guard bool(environment["MINTO_EMPTY_FINAL_REPAIR"]) else {
            return .disabled
        }

        return EmptyFinalRepairPolicy(
            isEnabled: true,
            padSeconds: nonNegativeDouble(environment["MINTO_EMPTY_FINAL_REPAIR_PAD_SEC"]) ?? 1.0,
            minChunkSeconds: nonNegativeDouble(environment["MINTO_EMPTY_FINAL_REPAIR_MIN_CHUNK_SEC"]) ?? 2.0,
            minAudioDB: Float(double(environment["MINTO_EMPTY_FINAL_REPAIR_MIN_AUDIO_DB"]) ?? -35.0),
            maxBufferedSeconds: nonNegativeDouble(environment["MINTO_EMPTY_FINAL_REPAIR_BUFFER_SEC"]) ?? 45.0
        )
    }

    func allowsRetry(for chunk: AudioChunk, audioDB: Float) -> Bool {
        guard isEnabled else { return false }
        guard padSeconds > 0 else { return false }
        guard chunk.durationSeconds >= minChunkSeconds else { return false }
        guard audioDB >= minAudioDB else { return false }
        guard chunk.startSeconds != nil, chunk.endSeconds != nil else { return false }
        return true
    }

    private static func bool(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func nonNegativeDouble(_ value: String?) -> Double? {
        guard let parsed = double(value), parsed >= 0 else { return nil }
        return parsed
    }

    private static func double(_ value: String?) -> Double? {
        guard let value,
              let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parsed.isFinite else {
            return nil
        }
        return parsed
    }
}

final class TranscriptionAudioSampleBuffer: @unchecked Sendable {
    private static let sampleRate = 16_000.0

    private let maxSampleCount: Int
    private let lock = NSLock()
    private var startSampleIndex = 0
    private var nextSampleIndex = 0
    private var samples: [Float] = []

    init(maxBufferedSeconds: Double) {
        self.maxSampleCount = max(0, Int(maxBufferedSeconds * Self.sampleRate))
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        startSampleIndex = 0
        nextSampleIndex = 0
        samples = []
    }

    func append(_ newSamples: [Float]) {
        guard maxSampleCount > 0, !newSamples.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        samples.append(contentsOf: newSamples)
        nextSampleIndex += newSamples.count

        let overflow = samples.count - maxSampleCount
        guard overflow > 0 else { return }
        samples.removeFirst(overflow)
        startSampleIndex += overflow
    }

    func paddedSamples(startSeconds: Double?, endSeconds: Double?, padSeconds: Double) -> [Float]? {
        guard let startSeconds, let endSeconds, endSeconds > startSeconds else { return nil }

        lock.lock()
        defer { lock.unlock() }

        let requestedStart = max(0, Int(((startSeconds - padSeconds) * Self.sampleRate).rounded(.down)))
        let requestedEnd = Int(((endSeconds + padSeconds) * Self.sampleRate).rounded(.up))

        guard requestedEnd > requestedStart,
              requestedStart >= startSampleIndex,
              requestedEnd <= nextSampleIndex else {
            return nil
        }

        let localStart = requestedStart - startSampleIndex
        let localEnd = requestedEnd - startSampleIndex
        guard localStart >= 0, localEnd <= samples.count, localEnd > localStart else { return nil }
        return Array(samples[localStart..<localEnd])
    }
}
