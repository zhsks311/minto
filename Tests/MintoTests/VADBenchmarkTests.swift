import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("VAD Benchmark (Manual Only)", .serialized)
struct VADBenchmarkTests {
    private static let sampleRate = 16_000

    private enum Candidate: String {
        case energy
        case silero
    }

    private static var candidate: Candidate {
        guard let rawValue = ProcessInfo.processInfo.environment["VAD_ENGINE"]?.lowercased(),
              !rawValue.isEmpty else {
            return .energy
        }
        return Candidate(rawValue: rawValue) ?? .energy
    }

    private static var rawDir: URL {
        if let value = ProcessInfo.processInfo.environment["MEETING_RAW_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: value)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/meeting/raw")
    }

    private static var audioURL: URL {
        rawDir.appendingPathComponent(ProcessInfo.processInfo.environment["MEETING_WAV"] ?? "haengan_20260526_full.wav")
    }

    private static var smiURL: URL {
        rawDir.appendingPathComponent(ProcessInfo.processInfo.environment["MEETING_SMI"] ?? "haengan_20260526_smi.json")
    }

    private static var maxSeconds: Double {
        positiveDoubleEnv("VAD_MAX_SECONDS", default: 120.0)
    }

    private static var frameSeconds: Double {
        positiveDoubleEnv("VAD_FRAME_SEC", default: 0.1)
    }

    private static var shortUtteranceSeconds: Double {
        positiveDoubleEnv("VAD_SHORT_UTTERANCE_SEC", default: 1.0)
    }

    @Test("sample/meeting VAD baseline metrics")
    func vadBaselineMetrics() async throws {
        guard ProcessInfo.processInfo.environment["RUN_VAD_BENCH"] == "1" else { return }

        guard FileManager.default.fileExists(atPath: Self.audioURL.path),
              FileManager.default.fileExists(atPath: Self.smiURL.path) else {
            print("[VADBench] 자료 없음 - skip (\(Self.audioURL.path), \(Self.smiURL.path))")
            return
        }

        let candidate = Self.candidate
        guard candidate == .energy else {
            let metrics = Self.unavailableMetrics(
                candidate: candidate,
                reason: "FluidAudio Silero VAD is not linked yet. Add the FluidAudio package before running VAD_ENGINE=silero."
            )
            try Self.writeMetricsIfNeeded(metrics)
            print("[VADBench] \(candidate.rawValue) unavailable: \(metrics.error ?? "")")
            return
        }

        let samples = try Self.readWAVSamples(from: Self.audioURL)
        let totalSeconds = min(Double(samples.count) / Double(Self.sampleRate), Self.maxSeconds)
        let captions = try Self.parseSMI(from: Self.smiURL)
        let captionIntervals = captions
            .filter { $0.start < totalSeconds && $0.end > 0 }
            .map { Interval(start: max(0, $0.start), end: min(totalSeconds, $0.end)) }
            .filter { $0.end > $0.start }
        let referenceIntervals = Self.mergedIntervals(captionIntervals)
        let shortReferenceIntervals = captionIntervals.filter {
            $0.end - $0.start <= Self.shortUtteranceSeconds
        }

        let detector: any VoiceActivityDetector = VADProcessor()
        nonisolated(unsafe) var finalChunks: [VADChunkMetric] = []
        nonisolated(unsafe) var previewChunks: [VADChunkMetric] = []

        detector.onChunk = { chunk in
            finalChunks.append(Self.metric(for: chunk, index: finalChunks.count))
        }
        detector.onPreviewChunk = { chunk in
            previewChunks.append(Self.metric(for: chunk, index: previewChunks.count))
        }

        let frameSize = max(1, Int(Self.frameSeconds * Double(Self.sampleRate)))
        let sampleLimit = min(samples.count, Int(totalSeconds * Double(Self.sampleRate)))
        var cursor = 0
        while cursor < sampleLimit {
            let end = min(sampleLimit, cursor + frameSize)
            detector.process(samples: Array(samples[cursor..<end]))
            cursor = end
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        if let pending = await detector.flushPending() {
            finalChunks.append(Self.metric(for: pending, index: finalChunks.count))
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        let finalIntervals = Self.mergedIntervals(finalChunks.map { Interval(start: $0.startSeconds, end: $0.endSeconds) })
        let referenceSpeechSeconds = Self.totalDuration(referenceIntervals)
        let finalSpeechSeconds = Self.totalDuration(finalIntervals)
        let coveredSpeechSeconds = Self.coveredDuration(of: referenceIntervals, by: finalIntervals)
        let falsePositiveSeconds = Self.falsePositiveDuration(of: finalIntervals, against: referenceIntervals)
        let missedSpeechSeconds = max(0, referenceSpeechSeconds - coveredSpeechSeconds)
        let coveredShortCount = shortReferenceIntervals.filter { interval in
            finalIntervals.contains { $0.overlaps(interval) }
        }.count

        let metrics = VADBenchmarkMetric(
            vad: candidate.rawValue,
            available: true,
            error: nil,
            sample: Self.audioURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_full", with: ""),
            seconds: totalSeconds,
            frameSeconds: Self.frameSeconds,
            chunkCount: finalChunks.count,
            previewCount: previewChunks.count,
            finalSpeechSeconds: finalSpeechSeconds,
            referenceSpeechSeconds: referenceSpeechSeconds,
            coveredSpeechSeconds: coveredSpeechSeconds,
            missedSpeechSeconds: missedSpeechSeconds,
            falsePositiveSeconds: falsePositiveSeconds,
            speechRecall: referenceSpeechSeconds > 0 ? coveredSpeechSeconds / referenceSpeechSeconds : 0,
            falsePositiveRatio: finalSpeechSeconds > 0 ? falsePositiveSeconds / finalSpeechSeconds : 0,
            shortUtteranceSeconds: Self.shortUtteranceSeconds,
            shortReferenceCount: shortReferenceIntervals.count,
            shortCoveredCount: coveredShortCount,
            shortRecall: shortReferenceIntervals.isEmpty ? 0 : Double(coveredShortCount) / Double(shortReferenceIntervals.count),
            chunks: finalChunks,
            previews: previewChunks
        )
        try Self.writeMetricsIfNeeded(metrics)

        print("""

        === VAD Benchmark [\(candidate.rawValue)] ===
        audio                  : \(Self.audioURL.lastPathComponent)
        seconds                : \(String(format: "%.1f", totalSeconds))
        chunks / previews      : \(finalChunks.count) / \(previewChunks.count)
        speech recall          : \(String(format: "%.1f%%", metrics.speechRecall * 100)) (\(String(format: "%.1f", coveredSpeechSeconds))/\(String(format: "%.1f", referenceSpeechSeconds))s)
        false positive seconds : \(String(format: "%.1f", falsePositiveSeconds))s (ratio \(String(format: "%.1f%%", metrics.falsePositiveRatio * 100)))
        missed speech seconds  : \(String(format: "%.1f", missedSpeechSeconds))s
        short recall           : \(coveredShortCount)/\(shortReferenceIntervals.count) <= \(String(format: "%.1f", Self.shortUtteranceSeconds))s
        ================================

        """)

        #expect(referenceSpeechSeconds > 0, "VAD benchmark reference speech should not be empty")
        #expect(!finalChunks.isEmpty, "Energy VAD should produce baseline chunks for sample speech")
    }

    private static func unavailableMetrics(candidate: Candidate, reason: String) -> VADBenchmarkMetric {
        VADBenchmarkMetric(
            vad: candidate.rawValue,
            available: false,
            error: reason,
            sample: Self.audioURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_full", with: ""),
            seconds: 0,
            frameSeconds: Self.frameSeconds,
            chunkCount: 0,
            previewCount: 0,
            finalSpeechSeconds: 0,
            referenceSpeechSeconds: 0,
            coveredSpeechSeconds: 0,
            missedSpeechSeconds: 0,
            falsePositiveSeconds: 0,
            speechRecall: 0,
            falsePositiveRatio: 0,
            shortUtteranceSeconds: Self.shortUtteranceSeconds,
            shortReferenceCount: 0,
            shortCoveredCount: 0,
            shortRecall: 0,
            chunks: [],
            previews: []
        )
    }

    nonisolated private static func metric(for chunk: AudioChunk, index: Int) -> VADChunkMetric {
        let start = chunk.startSeconds ?? 0
        let end = chunk.endSeconds ?? start + chunk.durationSeconds
        return VADChunkMetric(
            index: index,
            startSeconds: start,
            endSeconds: end,
            durationSeconds: chunk.durationSeconds,
            trailingSilence: chunk.trailingSilence,
            isPreview: chunk.isPreview,
            sampleCount: chunk.samples.count
        )
    }

    private static func writeMetricsIfNeeded(_ metrics: VADBenchmarkMetric) throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["VAD_OUTPUT_DIR"]
            .flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0) }) else {
            return
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metrics)
        try data.write(to: outputDirectory.appendingPathComponent("\(metrics.sample)_vad_\(metrics.vad)_metrics.json"))
    }

    private static func positiveDoubleEnv(_ key: String, default defaultValue: Double) -> Double {
        guard let rawValue = ProcessInfo.processInfo.environment[key],
              let value = Double(rawValue),
              value > 0 else {
            return defaultValue
        }
        return value
    }

    private struct SMIDocument: Decodable {
        let smiList: [Caption]
    }

    private struct Caption: Decodable {
        let start: Double
        let end: Double
        let cc: String
    }

    private static func parseSMI(from url: URL) throws -> [Caption] {
        let data = try Data(contentsOf: url)
        let doc = try JSONDecoder().decode(SMIDocument.self, from: data)
        return doc.smiList
            .filter { !$0.cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
    }

    private static func readWAVSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count >= 12,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            throw NSError(domain: "VADBench", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "WAV RIFF header missing: \(url.path)"
            ])
        }

        var audioFormat: UInt16?
        var channelCount: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var dataRange: Range<Int>?
        var offset = 12

        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<offset + 4], encoding: .ascii) ?? ""
            let chunkSize = Int(readUInt32LE(data, offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(chunkStart + chunkSize, data.count)

            if chunkID == "fmt ", chunkStart + 16 <= chunkEnd {
                audioFormat = readUInt16LE(data, chunkStart)
                channelCount = readUInt16LE(data, chunkStart + 2)
                sampleRate = readUInt32LE(data, chunkStart + 4)
                bitsPerSample = readUInt16LE(data, chunkStart + 14)
            } else if chunkID == "data" {
                dataRange = chunkStart..<chunkEnd
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard channelCount == 1, sampleRate == 16_000 else {
            throw NSError(domain: "VADBench", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "WAV must be 16kHz mono: \(url.path)"
            ])
        }
        guard let audioFormat, let bitsPerSample, let dataRange else {
            throw NSError(domain: "VADBench", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "WAV fmt/data chunk missing: \(url.path)"
            ])
        }

        switch (audioFormat, bitsPerSample) {
        case (1, 16):
            return stride(from: dataRange.lowerBound, to: dataRange.upperBound - 1, by: 2).map { index in
                let sample = Int16(bitPattern: readUInt16LE(data, index))
                return max(-1.0, Float(sample) / 32768.0)
            }
        case (3, 32):
            return stride(from: dataRange.lowerBound, to: dataRange.upperBound - 3, by: 4).map { index in
                Float(bitPattern: readUInt32LE(data, index))
            }
        default:
            throw NSError(domain: "VADBench", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported WAV format: format=\(audioFormat), bits=\(bitsPerSample)"
            ])
        }
    }

    private static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func mergedIntervals(_ intervals: [Interval]) -> [Interval] {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var merged: [Interval] = []
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = Interval(start: current.start, end: max(current.end, interval.end))
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    private static func totalDuration(_ intervals: [Interval]) -> Double {
        intervals.reduce(0) { $0 + max(0, $1.end - $1.start) }
    }

    private static func coveredDuration(of references: [Interval], by detections: [Interval]) -> Double {
        references.reduce(0) { total, reference in
            total + detections.reduce(0) { subtotal, detection in
                subtotal + reference.overlap(with: detection)
            }
        }
    }

    private static func falsePositiveDuration(of detections: [Interval], against references: [Interval]) -> Double {
        detections.reduce(0) { total, detection in
            let covered = references.reduce(0) { $0 + detection.overlap(with: $1) }
            return total + max(0, detection.end - detection.start - covered)
        }
    }
}

private struct VADBenchmarkMetric: Codable {
    let vad: String
    let available: Bool
    let error: String?
    let sample: String
    let seconds: Double
    let frameSeconds: Double
    let chunkCount: Int
    let previewCount: Int
    let finalSpeechSeconds: Double
    let referenceSpeechSeconds: Double
    let coveredSpeechSeconds: Double
    let missedSpeechSeconds: Double
    let falsePositiveSeconds: Double
    let speechRecall: Double
    let falsePositiveRatio: Double
    let shortUtteranceSeconds: Double
    let shortReferenceCount: Int
    let shortCoveredCount: Int
    let shortRecall: Double
    let chunks: [VADChunkMetric]
    let previews: [VADChunkMetric]

    enum CodingKeys: String, CodingKey {
        case vad
        case available
        case error
        case sample
        case seconds
        case frameSeconds = "frame_seconds"
        case chunkCount = "chunk_count"
        case previewCount = "preview_count"
        case finalSpeechSeconds = "final_speech_seconds"
        case referenceSpeechSeconds = "reference_speech_seconds"
        case coveredSpeechSeconds = "covered_speech_seconds"
        case missedSpeechSeconds = "missed_speech_seconds"
        case falsePositiveSeconds = "false_positive_seconds"
        case speechRecall = "speech_recall"
        case falsePositiveRatio = "false_positive_ratio"
        case shortUtteranceSeconds = "short_utterance_seconds"
        case shortReferenceCount = "short_reference_count"
        case shortCoveredCount = "short_covered_count"
        case shortRecall = "short_recall"
        case chunks
        case previews
    }
}

private struct VADChunkMetric: Codable {
    let index: Int
    let startSeconds: Double
    let endSeconds: Double
    let durationSeconds: Double
    let trailingSilence: Double
    let isPreview: Bool
    let sampleCount: Int

    enum CodingKeys: String, CodingKey {
        case index
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case durationSeconds = "duration_seconds"
        case trailingSilence = "trailing_silence"
        case isPreview = "is_preview"
        case sampleCount = "sample_count"
    }
}

private struct Interval {
    let start: Double
    let end: Double

    func overlaps(_ other: Interval) -> Bool {
        overlap(with: other) > 0
    }

    func overlap(with other: Interval) -> Double {
        max(0, min(end, other.end) - max(start, other.start))
    }
}
