import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("Streaming Chunk Benchmark (Manual Only)", .serialized)
struct StreamingChunkBenchmarkTests {
    private static let sampleRate = 16_000

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
        positiveDoubleEnv("STREAM_MAX_SECONDS", default: 120.0)
    }

    private static var previewStepSeconds: Double {
        positiveDoubleEnv("STREAM_PREVIEW_STEP_SEC", default: 1.0)
    }

    private static var previewContextSeconds: Double {
        positiveDoubleEnv("STREAM_PREVIEW_CONTEXT_SEC", default: 8.0)
    }

    private static var finalWindowSeconds: Double {
        positiveDoubleEnv("STREAM_FINAL_WINDOW_SEC", default: 5.0)
    }

    @Test("rolling preview/final chunk CER and latency metrics")
    func rollingPreviewFinalBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1",
              ProcessInfo.processInfo.environment["RUN_STREAMING_BENCH"] == "1" else {
            return
        }

        guard FileManager.default.fileExists(atPath: Self.audioURL.path),
              FileManager.default.fileExists(atPath: Self.smiURL.path) else {
            print("[StreamingBench] 자료 없음 - skip (\(Self.audioURL.path), \(Self.smiURL.path))")
            return
        }

        let samples = try Self.readWAVSamples(from: Self.audioURL)
        let totalSeconds = min(Double(samples.count) / Double(Self.sampleRate), Self.maxSeconds)
        let captions = try Self.parseSMI(from: Self.smiURL)
        let reference = Self.referenceText(captions: captions, start: 0, end: totalSeconds)

        let service = try await STTBenchmarkEngineSupport.loadService()
        guard case .loaded = service.modelState else {
            Issue.record("엔진 로드 실패: \(service.modelState)")
            return
        }
        let engineLabel = STTBenchmarkEngineSupport.displayName(for: service)

        var previewEvents = 0
        var previewNonEmpty = 0
        var previewRevisions = 0
        var previewEditDistanceTotal = 0
        var firstPreviewAt: Double?
        var lastPreviewText = ""
        var lastPreviewForFinal = ""
        var previewRTFs: [Double] = []
        var previewTimeline: [STTBenchmarkPreviewSegmentMetric] = []

        var finalEvents = 0
        var emptyFinals = 0
        var finalRTFs: [Double] = []
        var finalElapsedSeconds: [Double] = []
        var allFinalTexts: [String] = []
        var lastPreviewFinalDistanceTotal = 0
        var finalWindows: [STTBenchmarkSegmentMetric] = []
        var totalFinalDistance = 0
        var totalFinalRefLen = 0
        var falsePositiveFinalCount = 0
        var falsePositiveFinalChars = 0

        let benchmarkStartedAt = Date()
        var t = Self.previewStepSeconds
        while t <= totalSeconds {
            previewEvents += 1

            if service.supportsPreviewTranscription {
                let contextStart = max(0, t - Self.previewContextSeconds)
                let clip = Self.slice(samples, start: contextStart, end: t)
                let measured = try await Self.transcribeMeasured(service: service, samples: clip)
                previewRTFs.append(measured.rtf)

                let text = measured.text.trimmingCharacters(in: .whitespacesAndNewlines)
                var revisionDistance: Int?
                if !text.isEmpty {
                    previewNonEmpty += 1
                    if firstPreviewAt == nil {
                        firstPreviewAt = t
                    }
                    if !lastPreviewText.isEmpty, text != lastPreviewText {
                        previewRevisions += 1
                        let distance = Self.editDistance(Array(lastPreviewText), Array(text))
                        previewEditDistanceTotal += distance
                        revisionDistance = distance
                    }
                    lastPreviewText = text
                    lastPreviewForFinal = text
                }
                previewTimeline.append(STTBenchmarkPreviewSegmentMetric(
                    index: previewEvents - 1,
                    audioSeconds: t,
                    contextStartSeconds: contextStart,
                    contextEndSeconds: t,
                    text: text,
                    rtf: measured.rtf,
                    revisionDistance: revisionDistance
                ))
            }

            if t.truncatingRemainder(dividingBy: Self.finalWindowSeconds) < Self.previewStepSeconds {
                let finalStart = max(0, t - Self.finalWindowSeconds)
                let finalClip = Self.slice(samples, start: finalStart, end: t)
                let finalMeasured = try await Self.transcribeMeasured(service: service, samples: finalClip)
                let finalText = finalMeasured.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalReference = Self.referenceText(captions: captions, start: finalStart, end: t)
                let finalStats = Self.cerStats(reference: finalReference, hypothesis: finalText)
                let finalHypLength = STTBenchmarkTextMetrics.normalizedLength(finalText)
                finalEvents += 1
                finalRTFs.append(finalMeasured.rtf)
                finalElapsedSeconds.append(finalMeasured.elapsedSeconds)
                if finalText.isEmpty {
                    emptyFinals += 1
                }
                if finalStats.refLen == 0, finalHypLength > 0 {
                    falsePositiveFinalCount += 1
                    falsePositiveFinalChars += finalHypLength
                }
                if !lastPreviewForFinal.isEmpty || !finalText.isEmpty {
                    let distance = Self.editDistance(Array(lastPreviewForFinal), Array(finalText))
                    lastPreviewFinalDistanceTotal += distance
                }
                totalFinalDistance += finalStats.distance
                totalFinalRefLen += finalStats.refLen
                allFinalTexts.append(finalText)
                finalWindows.append(STTBenchmarkSegmentMetric(
                    index: finalEvents - 1,
                    startSeconds: finalStart,
                    endSeconds: t,
                    durationSeconds: t - finalStart,
                    reference: finalReference,
                    hypothesis: finalText,
                    referenceLength: finalStats.refLen,
                    hypothesisLength: finalHypLength,
                    distance: finalStats.distance,
                    cer: finalStats.refLen > 0 ? Double(finalStats.distance) / Double(finalStats.refLen) : 0,
                    elapsedSeconds: finalMeasured.elapsedSeconds,
                    rtf: finalMeasured.rtf,
                    empty: finalText.isEmpty
                ))
                lastPreviewForFinal = ""
            }

            t += Self.previewStepSeconds
        }

        let stats = Self.cerStats(reference: reference, hypothesis: allFinalTexts.joined(separator: " "))
        let globalCER = stats.refLen > 0 ? Double(stats.distance) / Double(stats.refLen) : 0
        let avgPreviewRevisionDistance = previewRevisions > 0
            ? Double(previewEditDistanceTotal) / Double(previewRevisions)
            : 0
        let previewRTFP50 = Self.percentile(previewRTFs, 0.50)
        let previewRTFP95 = Self.percentile(previewRTFs, 0.95)
        let finalRTFP50 = Self.percentile(finalRTFs, 0.50)
        let finalRTFP95 = Self.percentile(finalRTFs, 0.95)
        let finalLatencySeconds = Self.percentile(finalElapsedSeconds, 0.50)
        let finalAudioSeconds = finalWindows.reduce(0) { $0 + $1.durationSeconds }
        let elapsedSeconds = Date().timeIntervalSince(benchmarkStartedAt)
        let microCER = totalFinalRefLen > 0 ? Double(totalFinalDistance) / Double(totalFinalRefLen) : 0

        try Self.writeStreamingMetricsIfNeeded(STTBenchmarkRunMetric(
            benchmarkKind: "rolling_preview_final",
            engineID: service.speechEngineID.rawValue,
            engineLabel: engineLabel,
            modelID: service.speechEngineID.whisperVariant == nil ? "" : service.modelVariant,
            sampleID: Self.audioURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_full", with: ""),
            supportsPreview: service.supportsPreviewTranscription,
            benchmarkSeconds: totalSeconds,
            totalUnitCount: finalEvents,
            measuredUnitCount: finalWindows.count,
            referenceLength: totalFinalRefLen,
            hypothesisLength: STTBenchmarkTextMetrics.hypothesisLength(finalWindows),
            distance: totalFinalDistance,
            microCER: microCER,
            macroCER: STTBenchmarkTextMetrics.macroCER(finalWindows),
            globalDistance: stats.distance,
            globalReferenceLength: stats.refLen,
            globalCER: globalCER,
            emptyFinalCount: emptyFinals,
            falsePositiveTranscriptCount: falsePositiveFinalCount,
            falsePositiveTranscriptChars: falsePositiveFinalChars,
            audioSeconds: finalAudioSeconds,
            elapsedSeconds: elapsedSeconds,
            rtf: finalAudioSeconds > 0 ? elapsedSeconds / finalAudioSeconds : 0,
            peakMemoryMB: STTBenchmarkProcessMetrics.peakResidentMemoryMB(),
            metadata: [
                "preview_step_seconds": "\(Self.previewStepSeconds)",
                "preview_context_seconds": "\(Self.previewContextSeconds)",
                "final_window_seconds": "\(Self.finalWindowSeconds)",
                "preview_edit_distance_total": "\(previewEditDistanceTotal)",
                "avg_preview_revision_distance": "\(avgPreviewRevisionDistance)",
                "preview_rtf_p50": "\(previewRTFP50)",
                "preview_rtf_p95": "\(previewRTFP95)",
                "final_rtf_p50": "\(finalRTFP50)",
                "final_rtf_p95": "\(finalRTFP95)",
                "last_preview_final_edit_distance": "\(lastPreviewFinalDistanceTotal)",
            ],
            streaming: STTBenchmarkStreamingSummary(
                firstPartialLatencySeconds: firstPreviewAt,
                partialRevisionCount: previewRevisions,
                finalLatencySeconds: finalLatencySeconds,
                finalCER: globalCER,
                unstablePartialRatio: previewEvents > 0 ? Double(previewRevisions) / Double(previewEvents) : 0,
                previewEvents: previewEvents,
                previewNonEmpty: previewNonEmpty,
                finalEvents: finalEvents
            ),
            segments: finalWindows,
            previewSegments: previewTimeline
        ))

        print("""

        === Streaming Chunk Benchmark [\(engineLabel)] ===
        audio                  : \(Self.audioURL.lastPathComponent)
        seconds                : \(String(format: "%.1f", totalSeconds))
        preview support        : \(service.supportsPreviewTranscription ? "enabled" : "disabled")
        preview step/context   : \(String(format: "%.1f", Self.previewStepSeconds))s / \(String(format: "%.1f", Self.previewContextSeconds))s
        final window           : \(String(format: "%.1f", Self.finalWindowSeconds))s
        preview events         : \(previewEvents) (non-empty \(previewNonEmpty))
        preview revisions      : \(previewRevisions) (avg edit \(String(format: "%.1f", avgPreviewRevisionDistance)))
        first preview latency  : \(String(format: "%.1f", firstPreviewAt ?? -1))s audio-time
        final events           : \(finalEvents) (empty \(emptyFinals))
        preview RTF p50/p95    : \(String(format: "%.2f", previewRTFP50)) / \(String(format: "%.2f", previewRTFP95))
        final RTF p50/p95      : \(String(format: "%.2f", finalRTFP50)) / \(String(format: "%.2f", finalRTFP95))
        last-preview final edit: \(lastPreviewFinalDistanceTotal)
        global CER             : \(String(format: "%.1f%%", globalCER * 100)) (distance \(stats.distance) / ref \(stats.refLen))
        ================================

        """)

        #expect(stats.refLen > 0, "streaming benchmark reference should not be empty")
    }

    @Test("sample transcript raw chunks vs normalized blocks A/B")
    func transcriptNormalizerABBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1",
              ProcessInfo.processInfo.environment["RUN_TRANSCRIPT_AB"] == "1" else {
            return
        }

        guard FileManager.default.fileExists(atPath: Self.audioURL.path),
              FileManager.default.fileExists(atPath: Self.smiURL.path) else {
            print("[TranscriptAB] 자료 없음 - skip (\(Self.audioURL.path), \(Self.smiURL.path))")
            return
        }

        let windowSeconds = Self.positiveDoubleEnv("TRANSCRIPT_AB_WINDOW_SEC", default: 15.0)
        let samples = try Self.readWAVSamples(from: Self.audioURL)
        let totalSeconds = min(Double(samples.count) / Double(Self.sampleRate), Self.maxSeconds)
        let captions = try Self.parseSMI(from: Self.smiURL)
        let reference = Self.referenceText(captions: captions, start: 0, end: totalSeconds)

        let service = try await STTBenchmarkEngineSupport.loadService()
        guard case .loaded = service.modelState else {
            Issue.record("엔진 로드 실패: \(service.modelState)")
            return
        }
        let engineLabel = STTBenchmarkEngineSupport.displayName(for: service)

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var rawSegments: [Segment] = []
        var t = 0.0
        while t < totalSeconds {
            let end = min(totalSeconds, t + windowSeconds)
            let clip = Self.slice(samples, start: t, end: end)
            let measured = try await Self.transcribeMeasured(service: service, samples: clip)
            let text = measured.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !text.isEmpty {
                rawSegments.append(Segment(
                    text: text,
                    timestamp: startedAt.addingTimeInterval(t),
                    duration: end - t
                ))
            }
            t = end
        }

        let normalizedSegments = TranscriptNormalizer.normalize(rawSegments)
        let rawText = rawSegments.map(\.text).joined(separator: " ")
        let normalizedText = normalizedSegments.map(\.text).joined(separator: " ")
        let rawStats = Self.cerStats(reference: reference, hypothesis: rawText)
        let normalizedStats = Self.cerStats(reference: reference, hypothesis: normalizedText)
        let rawCER = rawStats.refLen > 0 ? Double(rawStats.distance) / Double(rawStats.refLen) : 0
        let normalizedCER = normalizedStats.refLen > 0
            ? Double(normalizedStats.distance) / Double(normalizedStats.refLen)
            : 0
        let rawDangling = rawSegments.filter { TranscriptNormalizer.isLikelyIncompleteEnding($0.text) }.count
        let normalizedDangling = normalizedSegments.filter { TranscriptNormalizer.isLikelyIncompleteEnding($0.text) }.count

        print("""

        === Transcript Normalizer A/B [\(engineLabel)] ===
        audio                  : \(Self.audioURL.lastPathComponent)
        seconds                : \(String(format: "%.1f", totalSeconds))
        raw window             : \(String(format: "%.1f", windowSeconds))s
        raw segments           : \(rawSegments.count) (dangling endings \(rawDangling))
        normalized segments    : \(normalizedSegments.count) (dangling endings \(normalizedDangling))
        segment reduction      : \(rawSegments.count - normalizedSegments.count)
        raw global CER         : \(String(format: "%.1f%%", rawCER * 100)) (distance \(rawStats.distance) / ref \(rawStats.refLen))
        normalized global CER  : \(String(format: "%.1f%%", normalizedCER * 100)) (distance \(normalizedStats.distance) / ref \(normalizedStats.refLen))
        raw preview            : \(rawSegments.prefix(3).map(\.text).joined(separator: " / ").prefix(260))
        normalized preview     : \(normalizedSegments.prefix(3).map(\.text).joined(separator: " / ").prefix(260))
        ================================
        ※ 같은 STT 결과를 재배열하므로 CER 변화는 없어야 한다. 이 A/B는 정확도보다 저장 transcript 가독성 지표다.

        """)

        #expect(rawStats.refLen > 0, "transcript A/B reference should not be empty")
        #expect(normalizedSegments.count <= rawSegments.count)
        #expect(rawStats.distance == normalizedStats.distance, "normalization should not alter transcript characters")
    }

    private static func transcribeMeasured(service: STTService, samples: [Float]) async throws -> (
        text: String,
        elapsedSeconds: Double,
        rtf: Double
    ) {
        let startedAt = Date()
        let result = try await service.transcribe(pcmSamples: samples)
        let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
        let audioDuration = max(0.001, Double(samples.count) / Double(sampleRate))
        return (result.segment.text, elapsed, elapsed / audioDuration)
    }

    private static func writeStreamingMetricsIfNeeded(_ metrics: STTBenchmarkRunMetric) throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["STREAMING_OUTPUT_DIR"]
            .flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0) }) else {
            return
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metrics)
        try data.write(to: outputDirectory.appendingPathComponent("\(metrics.sampleID)_streaming_metrics.json"))
    }

    private static func positiveDoubleEnv(_ key: String, default defaultValue: Double) -> Double {
        guard let rawValue = ProcessInfo.processInfo.environment[key],
              let value = Double(rawValue),
              value > 0 else {
            return defaultValue
        }
        return value
    }

    private static func slice(_ samples: [Float], start: Double, end: Double) -> [Float] {
        let startSample = max(0, Int(start * Double(sampleRate)))
        let endSample = min(samples.count, Int(end * Double(sampleRate)))
        guard endSample > startSample else { return [] }
        return Array(samples[startSample..<endSample])
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
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

    private static func referenceText(captions: [Caption], start: Double, end: Double) -> String {
        captions
            .filter { $0.end >= start && $0.start <= end }
            .map { $0.cc.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
    }

    private static func readWAVSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count >= 12,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            throw NSError(domain: "StreamingBench", code: 1, userInfo: [
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
            throw NSError(domain: "StreamingBench", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "WAV must be 16kHz mono: \(url.path)"
            ])
        }
        guard let audioFormat, let bitsPerSample, let dataRange else {
            throw NSError(domain: "StreamingBench", code: 3, userInfo: [
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
            throw NSError(domain: "StreamingBench", code: 4, userInfo: [
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

    private static func cerStats(reference: String, hypothesis: String) -> (distance: Int, refLen: Int) {
        let strip: (String) -> [Character] = { text in
            Array(text.filter { !$0.isWhitespace && !$0.isPunctuation })
        }
        let ref = strip(reference)
        let hyp = strip(hypothesis)
        return (editDistance(ref, hyp), ref.count)
    }

    private static func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        let m = a.count
        let n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(0...n)
        for i in 1...m {
            var prev = dp[0]
            dp[0] = i
            for j in 1...n {
                let tmp = dp[j]
                dp[j] = a[i - 1] == b[j - 1]
                    ? prev
                    : Swift.min(prev, Swift.min(dp[j], dp[j - 1])) + 1
                prev = tmp
            }
        }
        return dp[n]
    }
}
