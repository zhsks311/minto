import Foundation
import Testing
@testable import MintoCore
#if canImport(FluidAudio)
import FluidAudio
#endif

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
        nonNegativeDoubleEnv("VAD_MAX_SECONDS") ?? 120.0
    }

    private static var frameSeconds: Double {
        positiveDoubleEnv("VAD_FRAME_SEC", default: 0.1)
    }

    private static var shortUtteranceSeconds: Double {
        positiveDoubleEnv("VAD_SHORT_UTTERANCE_SEC", default: 1.0)
    }

    private static var sileroThreshold: Float {
        Float(positiveDoubleEnv("SILERO_VAD_THRESHOLD", default: 0.5))
    }

    private static var energyNoiseOffsetDB: Float {
        Float(nonNegativeDoubleEnv("ENERGY_VAD_NOISE_OFFSET_DB") ?? 10.0)
    }

    private static var sileroMinSpeechSeconds: Double {
        positiveDoubleEnv("SILERO_MIN_SPEECH_SEC", default: 0.25)
    }

    private static var sileroMinSilenceSeconds: Double {
        positiveDoubleEnv("SILERO_MIN_SILENCE_SEC", default: 0.4)
    }

    private static var sileroSpeechPaddingSeconds: Double {
        nonNegativeDoubleEnv("SILERO_SPEECH_PADDING_SEC") ?? 0.12
    }

    private static var sileroMaxSpeechSeconds: Double {
        positiveDoubleEnv("SILERO_MAX_SPEECH_SEC", default: 14.0)
    }

    private static var chunkMergeGapSeconds: Double? {
        nonNegativeDoubleEnv("VAD_MERGE_GAP_SEC")
    }

    private static var chunkMergeMaxSeconds: Double {
        positiveDoubleEnv("VAD_MERGE_MAX_SEC", default: 15.0)
    }

    private static var fluidAudioModelDirectory: URL {
        if let value = ProcessInfo.processInfo.environment["FLUIDAUDIO_MODEL_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: value)
        }
        return URL(fileURLWithPath: "/private/tmp/minto2-fluidaudio-models", isDirectory: true)
    }

    private static var maxSTTChunks: Int {
        guard let value = ProcessInfo.processInfo.environment["VAD_STT_MAX_CHUNKS"].flatMap(Int.init),
              value >= 0 else {
            return 6
        }
        return value
    }

    private static var sttRepairPadSeconds: Double {
        nonNegativeDoubleEnv("VAD_STT_REPAIR_PAD_SEC") ?? 0
    }

    private static var shouldSkipSwiftGlobalCER: Bool {
        ProcessInfo.processInfo.environment["VAD_SKIP_SWIFT_GLOBAL_CER"] == "1"
    }

    private static var benchmarkConfig: VADBenchmarkConfigMetric {
        VADBenchmarkConfigMetric(
            energyNoiseOffsetDB: Double(Self.energyNoiseOffsetDB),
            sileroThreshold: Double(Self.sileroThreshold),
            sileroMinSpeechSeconds: Self.sileroMinSpeechSeconds,
            sileroMinSilenceSeconds: Self.sileroMinSilenceSeconds,
            sileroSpeechPaddingSeconds: Self.sileroSpeechPaddingSeconds,
            sileroMaxSpeechSeconds: Self.sileroMaxSpeechSeconds,
            chunkMergeGapSeconds: Self.chunkMergeGapSeconds,
            chunkMergeMaxSeconds: Self.chunkMergeMaxSeconds
        )
    }

    @Test("sample/meeting VAD baseline metrics")
    func vadBaselineMetrics() async throws {
        guard ProcessInfo.processInfo.environment["RUN_VAD_BENCH"] == "1" else { return }

        guard FileManager.default.fileExists(atPath: Self.audioURL.path),
              FileManager.default.fileExists(atPath: Self.smiURL.path) else {
            print("[VADBench] 자료 없음 - skip (\(Self.audioURL.path), \(Self.smiURL.path))")
            return
        }

        let samples = try Self.readWAVSamples(from: Self.audioURL)
        let totalSeconds = Self.evaluationSeconds(audioSeconds: Double(samples.count) / Double(Self.sampleRate))
        let captions = try Self.parseSMI(from: Self.smiURL)
        let candidate = Self.candidate

        if candidate == .silero {
            let rawFinalChunks = try await Self.sileroChunks(from: samples, totalSeconds: totalSeconds)
            let finalChunks = Self.prepareFinalChunks(rawFinalChunks)
            let metrics = Self.buildMetrics(
                candidate: candidate,
                captions: captions,
                totalSeconds: totalSeconds,
                rawChunkCount: rawFinalChunks.count,
                finalChunks: finalChunks,
                previewChunks: []
            )
            try Self.writeMetricsIfNeeded(metrics)
            Self.printMetrics(metrics, audioName: Self.audioURL.lastPathComponent)
            #expect(metrics.available, "Silero VAD benchmark should be available when FluidAudio is linked")
            #expect(!finalChunks.isEmpty, "Silero VAD should produce baseline chunks for sample speech")
            return
        }

        let (rawFinalChunks, previewChunks) = await Self.energyChunks(from: samples, totalSeconds: totalSeconds)
        let finalChunks = Self.prepareFinalChunks(rawFinalChunks)

        let metrics = Self.buildMetrics(
            candidate: candidate,
            captions: captions,
            totalSeconds: totalSeconds,
            rawChunkCount: rawFinalChunks.count,
            finalChunks: finalChunks,
            previewChunks: previewChunks
        )
        try Self.writeMetricsIfNeeded(metrics)
        Self.printMetrics(metrics, audioName: Self.audioURL.lastPathComponent)

        #expect(metrics.referenceSpeechSeconds > 0, "VAD benchmark reference speech should not be empty")
        #expect(!finalChunks.isEmpty, "Energy VAD should produce baseline chunks for sample speech")
    }

    @Test("sample/meeting VAD chunk STT CER metrics")
    func vadChunkSTTCER() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1",
              ProcessInfo.processInfo.environment["RUN_VAD_STT_BENCH"] == "1" else {
            return
        }

        guard FileManager.default.fileExists(atPath: Self.audioURL.path),
              FileManager.default.fileExists(atPath: Self.smiURL.path) else {
            print("[VADSTTBench] 자료 없음 - skip (\(Self.audioURL.path), \(Self.smiURL.path))")
            return
        }

        let samples = try Self.readWAVSamples(from: Self.audioURL)
        let totalSeconds = Self.evaluationSeconds(audioSeconds: Double(samples.count) / Double(Self.sampleRate))
        let captions = try Self.parseSMI(from: Self.smiURL)
        let candidate = Self.candidate
        let rawChunks: [VADChunkMetric]
        switch candidate {
        case .energy:
            rawChunks = await Self.energyChunks(from: samples, totalSeconds: totalSeconds).final
        case .silero:
            rawChunks = try await Self.sileroChunks(from: samples, totalSeconds: totalSeconds)
        }
        let allChunks = Self.prepareFinalChunks(rawChunks)
        let targetChunks = Self.maxSTTChunks > 0 ? Array(allChunks.prefix(Self.maxSTTChunks)) : allChunks
        guard !targetChunks.isEmpty else {
            Issue.record("VAD STT benchmark chunks should not be empty")
            return
        }

        let service = try await STTBenchmarkEngineSupport.loadService()
        guard case .loaded = service.modelState else {
            Issue.record("엔진 로드 실패: \(service.modelState)")
            return
        }

        let engineLabel = STTBenchmarkEngineSupport.displayName(for: service)
        let startedAt = Date()
        var totalDistance = 0
        var totalRefLen = 0
        var emptyCount = 0
        var falsePositiveTranscriptionCount = 0
        var falsePositiveTranscriptChars = 0
        var repairAttemptCount = 0
        var repairAcceptedCount = 0
        var repairAcceptedFalsePositiveCount = 0
        var chunkMetrics: [STTBenchmarkSegmentMetric] = []
        var allReferences: [String] = []
        var allHypotheses: [String] = []

        for (index, chunk) in targetChunks.enumerated() {
            let startSample = max(0, Int(chunk.startSeconds * Double(Self.sampleRate)))
            let endSample = min(samples.count, Int(chunk.endSeconds * Double(Self.sampleRate)))
            guard endSample > startSample else { continue }

            let reference = Self.referenceText(captions: captions, start: chunk.startSeconds, end: chunk.endSeconds)
            let clip = Array(samples[startSample..<endSample])
            let audioDB = Double(STTAudioUtilities.dbLevel(clip))
            let chunkStartedAt = Date()
            let result = try await service.transcribe(pcmSamples: clip)
            var hypothesis = result.segment.text
            var repairAttempted = false
            var repairAccepted = false
            var repairStartSeconds: Double?
            var repairEndSeconds: Double?
            var repairAudioDB: Double?
            if Self.sttRepairPadSeconds > 0,
               hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                repairAttempted = true
                repairAttemptCount += 1
                let repairStartSample = max(0, Int((chunk.startSeconds - Self.sttRepairPadSeconds) * Double(Self.sampleRate)))
                let repairEndSample = min(samples.count, Int((chunk.endSeconds + Self.sttRepairPadSeconds) * Double(Self.sampleRate)))
                if repairEndSample > repairStartSample {
                    let repairClip = Array(samples[repairStartSample..<repairEndSample])
                    repairStartSeconds = Double(repairStartSample) / Double(Self.sampleRate)
                    repairEndSeconds = Double(repairEndSample) / Double(Self.sampleRate)
                    repairAudioDB = Double(STTAudioUtilities.dbLevel(repairClip))
                    let repairResult = try await service.transcribe(pcmSamples: repairClip)
                    let repairedHypothesis = repairResult.segment.text
                    if !repairedHypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        hypothesis = repairedHypothesis
                        repairAccepted = true
                        repairAcceptedCount += 1
                    }
                }
            }
            let elapsedSeconds = Date().timeIntervalSince(chunkStartedAt)
            let stats = Self.cerStats(reference: reference, hypothesis: hypothesis)
            let normalizedHypLen = Self.normalizedCharacters(hypothesis).count
            let empty = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if empty {
                emptyCount += 1
            }
            if stats.refLen == 0, normalizedHypLen > 0 {
                falsePositiveTranscriptionCount += 1
                falsePositiveTranscriptChars += normalizedHypLen
            }
            let repairFalsePositive = repairAccepted && stats.refLen == 0 && normalizedHypLen > 0
            if repairFalsePositive {
                repairAcceptedFalsePositiveCount += 1
            }
            totalDistance += stats.distance
            totalRefLen += stats.refLen
            allReferences.append(reference)
            allHypotheses.append(hypothesis)
            chunkMetrics.append(STTBenchmarkSegmentMetric(
                index: index,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                durationSeconds: chunk.durationSeconds,
                audioDB: audioDB,
                reference: reference,
                hypothesis: hypothesis,
                referenceLength: stats.refLen,
                hypothesisLength: normalizedHypLen,
                distance: stats.distance,
                cer: stats.refLen > 0 ? Double(stats.distance) / Double(stats.refLen) : 0,
                elapsedSeconds: elapsedSeconds,
                rtf: chunk.durationSeconds > 0 ? elapsedSeconds / chunk.durationSeconds : 0,
                empty: empty,
                repairAttempted: Self.sttRepairPadSeconds > 0 ? repairAttempted : nil,
                repairAccepted: Self.sttRepairPadSeconds > 0 ? repairAccepted : nil,
                repairPadSeconds: Self.sttRepairPadSeconds > 0 ? Self.sttRepairPadSeconds : nil,
                repairStartSeconds: repairStartSeconds,
                repairEndSeconds: repairEndSeconds,
                repairDurationSeconds: repairStartSeconds.flatMap { start in
                    repairEndSeconds.map { $0 - start }
                },
                repairAudioDB: repairAudioDB,
                repairReferencePresent: repairAttempted ? stats.refLen > 0 : nil,
                repairFalsePositive: repairAttempted ? repairFalsePositive : nil
            ))
        }

        let globalStats = Self.shouldSkipSwiftGlobalCER ? nil : Self.cerStats(
            reference: allReferences.joined(separator: " "),
            hypothesis: allHypotheses.joined(separator: " ")
        )
        let fullReferenceGlobalStats = Self.shouldSkipSwiftGlobalCER ? nil : Self.cerStats(
            reference: Self.referenceText(captions: captions, start: 0, end: totalSeconds),
            hypothesis: allHypotheses.joined(separator: " ")
        )
        let elapsedSeconds = Date().timeIntervalSince(startedAt)
        let audioSeconds = chunkMetrics.reduce(0) { $0 + $1.durationSeconds }
        let metric = STTBenchmarkRunMetric(
            benchmarkKind: "vad_chunk_stt",
            engineID: service.speechEngineID.rawValue,
            engineLabel: engineLabel,
            modelID: service.speechEngineID.whisperVariant == nil ? "" : service.modelVariant,
            sampleID: Self.audioURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_full", with: ""),
            supportsPreview: service.supportsPreviewTranscription,
            benchmarkSeconds: totalSeconds,
            totalUnitCount: allChunks.count,
            measuredUnitCount: chunkMetrics.count,
            referenceLength: totalRefLen,
            hypothesisLength: STTBenchmarkTextMetrics.hypothesisLength(chunkMetrics),
            distance: totalDistance,
            microCER: totalRefLen > 0 ? Double(totalDistance) / Double(totalRefLen) : 0,
            macroCER: STTBenchmarkTextMetrics.macroCER(chunkMetrics),
            globalDistance: globalStats?.distance,
            globalReferenceLength: globalStats?.refLen,
            globalCER: globalStats.flatMap { $0.refLen > 0 ? Double($0.distance) / Double($0.refLen) : 0 },
            fullReferenceGlobalDistance: fullReferenceGlobalStats?.distance,
            fullReferenceGlobalReferenceLength: fullReferenceGlobalStats?.refLen,
            fullReferenceGlobalCER: fullReferenceGlobalStats.flatMap {
                $0.refLen > 0 ? Double($0.distance) / Double($0.refLen) : 0
            },
            emptyFinalCount: emptyCount,
            falsePositiveTranscriptCount: falsePositiveTranscriptionCount,
            falsePositiveTranscriptChars: falsePositiveTranscriptChars,
            audioSeconds: audioSeconds,
            elapsedSeconds: elapsedSeconds,
            rtf: audioSeconds > 0 ? elapsedSeconds / audioSeconds : 0,
            peakMemoryMB: STTBenchmarkProcessMetrics.peakResidentMemoryMB(),
            metadata: [
                "vad": candidate.rawValue,
                "raw_chunk_count": "\(rawChunks.count)",
                "total_chunk_count": "\(allChunks.count)",
                "measured_chunk_count": "\(chunkMetrics.count)",
                "energy_noise_offset_db": "\(Self.benchmarkConfig.energyNoiseOffsetDB)",
                "chunk_merge_gap_seconds": Self.formatOptionalSeconds(Self.benchmarkConfig.chunkMergeGapSeconds),
                "chunk_merge_max_seconds": "\(Self.benchmarkConfig.chunkMergeMaxSeconds)",
                "silero_threshold": "\(Self.benchmarkConfig.sileroThreshold)",
                "silero_min_speech_seconds": "\(Self.benchmarkConfig.sileroMinSpeechSeconds)",
                "silero_min_silence_seconds": "\(Self.benchmarkConfig.sileroMinSilenceSeconds)",
                "silero_speech_padding_seconds": "\(Self.benchmarkConfig.sileroSpeechPaddingSeconds)",
                "stt_repair_pad_seconds": "\(Self.sttRepairPadSeconds)",
                "stt_repair_attempt_count": "\(repairAttemptCount)",
                "stt_repair_accepted_count": "\(repairAcceptedCount)",
                "stt_repair_accepted_false_positive_count": "\(repairAcceptedFalsePositiveCount)",
                "skip_swift_global_cer": "\(Self.shouldSkipSwiftGlobalCER)",
            ],
            segments: chunkMetrics
        )
        try Self.writeSTTMetricsIfNeeded(metric)
        let globalDescription = metric.globalCER.map {
            "\(String(format: "%.1f%%", $0 * 100)) (distance \(metric.globalDistance ?? 0) / ref \(metric.globalReferenceLength ?? 0))"
        } ?? "skipped"
        let fullGlobalDescription = metric.fullReferenceGlobalCER.map {
            "\(String(format: "%.1f%%", $0 * 100)) (distance \(metric.fullReferenceGlobalDistance ?? 0) / ref \(metric.fullReferenceGlobalReferenceLength ?? 0))"
        } ?? "skipped"
        print("""

        === VAD STT Benchmark [\(candidate.rawValue) -> \(engineLabel)] ===
        chunks measured         : \(metric.measuredUnitCount)/\(metric.totalUnitCount) (raw \(rawChunks.count))
        merge gap / max         : \(Self.formatOptionalSeconds(Self.benchmarkConfig.chunkMergeGapSeconds)) / \(String(format: "%.1f", Self.benchmarkConfig.chunkMergeMaxSeconds))s
        repair pad / accepted   : \(String(format: "%.1f", Self.sttRepairPadSeconds))s / \(repairAcceptedCount)/\(repairAttemptCount)
        repair false positives  : \(repairAcceptedFalsePositiveCount)
        empty final count       : \(metric.emptyFinalCount)
        false positive text     : \(metric.falsePositiveTranscriptCount) chunks / \(metric.falsePositiveTranscriptChars) chars
        chunk CER               : \(String(format: "%.1f%%", metric.microCER * 100)) (distance \(metric.distance) / ref \(metric.referenceLength))
        covered global CER      : \(globalDescription)
        full reference CER      : \(fullGlobalDescription)
        RTF                     : \(String(format: "%.2f", metric.rtf))
        elapsed                 : \(String(format: "%.1f", metric.elapsedSeconds))s
        ==============================================

        """)

        #expect(metric.measuredUnitCount > 0)
        #expect(metric.referenceLength > 0)
    }

    @Test("VAD_MAX_SECONDS 0은 전체 길이로 처리한다")
    func maxSecondsZeroMeansFullDuration() {
        #expect(Self.cappedTotalSeconds(audioSeconds: 987, maxSeconds: 0) == 987)
        #expect(Self.cappedTotalSeconds(audioSeconds: 987, maxSeconds: 120) == 120)
        #expect(Self.cappedTotalSeconds(audioSeconds: 80, maxSeconds: 120) == 80)
    }

    private static func evaluationSeconds(audioSeconds: Double) -> Double {
        cappedTotalSeconds(audioSeconds: audioSeconds, maxSeconds: Self.maxSeconds)
    }

    private static func cappedTotalSeconds(audioSeconds: Double, maxSeconds: Double) -> Double {
        guard maxSeconds > 0 else { return audioSeconds }
        return min(audioSeconds, maxSeconds)
    }

    private static func buildMetrics(
        candidate: Candidate,
        captions: [Caption],
        totalSeconds: Double,
        rawChunkCount: Int,
        finalChunks: [VADChunkMetric],
        previewChunks: [VADChunkMetric]
    ) -> VADBenchmarkMetric {
        let captionIntervals = captions
            .filter { $0.start < totalSeconds && $0.end > 0 }
            .map { Interval(start: max(0, $0.start), end: min(totalSeconds, $0.end)) }
            .filter { $0.end > $0.start }
        let referenceIntervals = Self.mergedIntervals(captionIntervals)
        let shortReferenceIntervals = captionIntervals.filter {
            $0.end - $0.start <= Self.shortUtteranceSeconds
        }

        let finalIntervals = Self.mergedIntervals(finalChunks.map { Interval(start: $0.startSeconds, end: $0.endSeconds) })
        let referenceSpeechSeconds = Self.totalDuration(referenceIntervals)
        let finalSpeechSeconds = Self.totalDuration(finalIntervals)
        let coveredSpeechSeconds = Self.coveredDuration(of: referenceIntervals, by: finalIntervals)
        let falsePositiveSeconds = Self.falsePositiveDuration(of: finalIntervals, against: referenceIntervals)
        let missedSpeechSeconds = max(0, referenceSpeechSeconds - coveredSpeechSeconds)
        let coveredShortCount = shortReferenceIntervals.filter { interval in
            finalIntervals.contains { $0.overlaps(interval) }
        }.count

        return VADBenchmarkMetric(
            vad: candidate.rawValue,
            available: true,
            error: nil,
            config: Self.benchmarkConfig,
            sample: Self.audioURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_full", with: ""),
            seconds: totalSeconds,
            rawChunkCount: rawChunkCount,
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
    }

    private static func printMetrics(_ metrics: VADBenchmarkMetric, audioName: String) {
        print("""

        === VAD Benchmark [\(metrics.vad)] ===
        audio                  : \(audioName)
        seconds                : \(String(format: "%.1f", metrics.seconds))
        chunks / previews      : \(metrics.chunkCount) / \(metrics.previewCount) (raw \(metrics.rawChunkCount))
        merge gap / max        : \(Self.formatOptionalSeconds(metrics.config.chunkMergeGapSeconds)) / \(String(format: "%.1f", metrics.config.chunkMergeMaxSeconds))s
        speech recall          : \(String(format: "%.1f%%", metrics.speechRecall * 100)) (\(String(format: "%.1f", metrics.coveredSpeechSeconds))/\(String(format: "%.1f", metrics.referenceSpeechSeconds))s)
        false positive seconds : \(String(format: "%.1f", metrics.falsePositiveSeconds))s (ratio \(String(format: "%.1f%%", metrics.falsePositiveRatio * 100)))
        missed speech seconds  : \(String(format: "%.1f", metrics.missedSpeechSeconds))s
        short recall           : \(metrics.shortCoveredCount)/\(metrics.shortReferenceCount) <= \(String(format: "%.1f", metrics.shortUtteranceSeconds))s
        ================================

        """)
    }

    private static func sileroChunks(from samples: [Float], totalSeconds: Double) async throws -> [VADChunkMetric] {
        #if canImport(FluidAudio)
        let sampleLimit = min(samples.count, Int(totalSeconds * Double(Self.sampleRate)))
        let limitedSamples = Array(samples.prefix(sampleLimit))
        var segmentation = VadSegmentationConfig.default
        segmentation.minSpeechDuration = Self.sileroMinSpeechSeconds
        segmentation.minSilenceDuration = Self.sileroMinSilenceSeconds
        segmentation.maxSpeechDuration = Self.sileroMaxSpeechSeconds
        segmentation.speechPadding = Self.sileroSpeechPaddingSeconds

        let manager = try await VadManager(
            config: VadConfig(defaultThreshold: Self.sileroThreshold),
            modelDirectory: Self.fluidAudioModelDirectory
        )
        let segments = try await manager.segmentSpeech(limitedSamples, config: segmentation)
        return segments.enumerated().compactMap { index, segment in
            let startSample = max(0, segment.startSample(sampleRate: Self.sampleRate))
            let endSample = min(sampleLimit, segment.endSample(sampleRate: Self.sampleRate))
            guard endSample > startSample else { return nil }
            return VADChunkMetric(
                index: index,
                startSeconds: Double(startSample) / Double(Self.sampleRate),
                endSeconds: Double(endSample) / Double(Self.sampleRate),
                durationSeconds: Double(endSample - startSample) / Double(Self.sampleRate),
                trailingSilence: 0,
                isPreview: false,
                sampleCount: endSample - startSample
            )
        }
        #else
        throw NSError(domain: "VADBench", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "FluidAudio is not linked"
        ])
        #endif
    }

    private static func energyChunks(
        from samples: [Float],
        totalSeconds: Double
    ) async -> (final: [VADChunkMetric], previews: [VADChunkMetric]) {
        let detector: any VoiceActivityDetector = VADProcessor(noiseOffsetDB: Self.energyNoiseOffsetDB)
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
        return (finalChunks, previewChunks)
    }

    private static func prepareFinalChunks(_ chunks: [VADChunkMetric]) -> [VADChunkMetric] {
        guard let mergeGapSeconds = Self.chunkMergeGapSeconds else {
            return chunks
        }
        return Self.mergeChunks(chunks, maxGapSeconds: mergeGapSeconds, maxDurationSeconds: Self.chunkMergeMaxSeconds)
    }

    private static func mergeChunks(
        _ chunks: [VADChunkMetric],
        maxGapSeconds: Double,
        maxDurationSeconds: Double
    ) -> [VADChunkMetric] {
        let sorted = chunks.sorted {
            if $0.startSeconds == $1.startSeconds {
                return $0.endSeconds < $1.endSeconds
            }
            return $0.startSeconds < $1.startSeconds
        }
        guard var current = sorted.first else { return [] }
        var merged: [VADChunkMetric] = []

        for next in sorted.dropFirst() {
            let gap = max(0, next.startSeconds - current.endSeconds)
            let mergedStart = min(current.startSeconds, next.startSeconds)
            let mergedEnd = max(current.endSeconds, next.endSeconds)
            let mergedDuration = mergedEnd - mergedStart
            if gap <= maxGapSeconds, mergedDuration <= maxDurationSeconds {
                current = VADChunkMetric(
                    index: current.index,
                    startSeconds: mergedStart,
                    endSeconds: mergedEnd,
                    durationSeconds: mergedDuration,
                    trailingSilence: max(current.trailingSilence, next.trailingSilence),
                    isPreview: false,
                    sampleCount: max(0, Int((mergedDuration * Double(Self.sampleRate)).rounded()))
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged.enumerated().map { index, chunk in
            VADChunkMetric(
                index: index,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                durationSeconds: chunk.durationSeconds,
                trailingSilence: chunk.trailingSilence,
                isPreview: chunk.isPreview,
                sampleCount: chunk.sampleCount
            )
        }
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

    private static func writeSTTMetricsIfNeeded(_ metrics: STTBenchmarkRunMetric) throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["VAD_STT_OUTPUT_DIR"]
            .flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0) })
            ?? ProcessInfo.processInfo.environment["VAD_OUTPUT_DIR"]
                .flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0) }) else {
            return
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metrics)
        let engine = metrics.engineLabel
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let vad = metrics.metadata["vad"] ?? "unknown"
        try data.write(to: outputDirectory.appendingPathComponent("\(metrics.sampleID)_vad_\(vad)_stt_\(engine).json"))
    }

    private static func positiveDoubleEnv(_ key: String, default defaultValue: Double) -> Double {
        guard let rawValue = ProcessInfo.processInfo.environment[key],
              let value = Double(rawValue),
              value > 0 else {
            return defaultValue
        }
        return value
    }

    private static func nonNegativeDoubleEnv(_ key: String) -> Double? {
        guard let rawValue = ProcessInfo.processInfo.environment[key],
              let value = Double(rawValue),
              value >= 0 else {
            return nil
        }
        return value
    }

    private static func formatOptionalSeconds(_ value: Double?) -> String {
        guard let value else { return "disabled" }
        return String(format: "%.1f", value)
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
            .filter { min($0.end, end) > max($0.start, start) }
            .map(\.cc)
            .joined(separator: " ")
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

    private static func cerStats(reference: String, hypothesis: String) -> (distance: Int, refLen: Int) {
        let ref = normalizedCharacters(reference)
        let hyp = normalizedCharacters(hypothesis)
        return (editDistance(ref, hyp), ref.count)
    }

    private static func normalizedCharacters(_ text: String) -> [Character] {
        Array(text.filter { !$0.isWhitespace && !$0.isPunctuation })
    }

    private static func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        let m = a.count
        let n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(0...n)
        for i in 1...m {
            var previous = dp[0]
            dp[0] = i
            for j in 1...n {
                let old = dp[j]
                dp[j] = a[i - 1] == b[j - 1]
                    ? previous
                    : Swift.min(previous, Swift.min(dp[j], dp[j - 1])) + 1
                previous = old
            }
        }
        return dp[n]
    }
}

private struct VADBenchmarkMetric: Codable {
    let vad: String
    let available: Bool
    let error: String?
    let config: VADBenchmarkConfigMetric
    let sample: String
    let seconds: Double
    let rawChunkCount: Int
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
        case config
        case sample
        case seconds
        case rawChunkCount = "raw_chunk_count"
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

private struct VADBenchmarkConfigMetric: Codable {
    let energyNoiseOffsetDB: Double
    let sileroThreshold: Double
    let sileroMinSpeechSeconds: Double
    let sileroMinSilenceSeconds: Double
    let sileroSpeechPaddingSeconds: Double
    let sileroMaxSpeechSeconds: Double
    let chunkMergeGapSeconds: Double?
    let chunkMergeMaxSeconds: Double

    enum CodingKeys: String, CodingKey {
        case energyNoiseOffsetDB = "energy_noise_offset_db"
        case sileroThreshold = "silero_threshold"
        case sileroMinSpeechSeconds = "silero_min_speech_seconds"
        case sileroMinSilenceSeconds = "silero_min_silence_seconds"
        case sileroSpeechPaddingSeconds = "silero_speech_padding_seconds"
        case sileroMaxSpeechSeconds = "silero_max_speech_seconds"
        case chunkMergeGapSeconds = "chunk_merge_gap_seconds"
        case chunkMergeMaxSeconds = "chunk_merge_max_seconds"
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
