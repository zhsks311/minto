import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("Product Path Meeting Corpus Evaluation (Manual Only)", .serialized)
struct ProductPathMeetingCorpusTests {

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

    private static let sampleRate = 16_000

    private static var windowSeconds: Double {
        positiveDoubleEnv("MEETING_WINDOW_SEC", default: 30.0)
    }

    private static var maxWindows: Int {
        ProcessInfo.processInfo.environment["MEETING_MAX_WINDOWS"].flatMap(Int.init) ?? 1
    }

    private static var maxGapSeconds: Double {
        positiveDoubleEnv("MEETING_MAX_GAP_SEC", default: 3.0)
    }

    private static var audioPaddingSeconds: Double {
        nonNegativeDoubleEnv("MEETING_AUDIO_PAD_SEC") ?? 0
    }

    private static var minWindowSeconds: Double {
        nonNegativeDoubleEnv("MEETING_MIN_WINDOW_SEC") ?? 0
    }

    private static var maxCaptionsPerWindow: Int {
        nonNegativeIntEnv("MEETING_MAX_CAPTIONS_PER_WINDOW") ?? 0
    }

    @Test("meeting WAV through TranscriptionViewModel product path")
    func productPathFinalBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1",
              ProcessInfo.processInfo.environment["RUN_PRODUCT_PATH_STT_TESTS"] == "1" else {
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: Self.audioURL.path),
              fileManager.fileExists(atPath: Self.smiURL.path) else {
            print("[ProductPath] sample missing - skip (\(Self.audioURL.lastPathComponent), \(Self.smiURL.lastPathComponent))")
            return
        }

        let captions = try Self.parseSMI(from: Self.smiURL)
        let windows = Self.mergeIntoWindows(captions, windowSeconds: Self.windowSeconds)
        let targetWindows = Self.maxWindows > 0 ? Array(windows.prefix(Self.maxWindows)) : windows
        guard !targetWindows.isEmpty else {
            Issue.record("product-path target window is empty")
            return
        }
        let samples = try Self.readWAVSamples(from: Self.audioURL)
        let fileAudioSeconds = Double(samples.count) / Double(Self.sampleRate)

        let loadStartedAt = Date()
        let service = try await STTBenchmarkEngineSupport.loadService()
        let coldStartSeconds = Date().timeIntervalSince(loadStartedAt)
        guard case .loaded = service.modelState else {
            if try Self.writeEngineUnavailableMarkerIfNeeded(service.modelState) {
                return
            }
            Issue.record("engine load failed: \(service.modelState)")
            return
        }

        let engineLabel = STTBenchmarkEngineSupport.displayName(for: service)
        let plan = TranscriptionCoordinatorPlan.make(engineID: service.speechEngineID)
        var segmentMetrics: [STTBenchmarkSegmentMetric] = []
        var allReferences: [String] = []
        var allHypotheses: [String] = []
        var totalDistance = 0
        var totalReferenceLength = 0
        var totalAudioSeconds = 0.0
        var totalElapsedSeconds = 0.0
        var emptyVisibleTranscriptCount = 0
        var userVisibleFallbackEventCount = 0
        var previewRevisionCount = 0
        var unstablePartialRatios: [Double] = []
        var firstVisibleSecondsValues: [Double] = []
        var finalDelaySecondsValues: [Double] = []

        for (index, window) in targetWindows.enumerated() {
            let cropStart = max(0, window.start - Self.audioPaddingSeconds)
            let cropEnd = min(fileAudioSeconds, window.end + Self.audioPaddingSeconds)
            let startSample = max(0, Int(cropStart * Double(Self.sampleRate)))
            let endSample = min(samples.count, Int(cropEnd * Double(Self.sampleRate)))
            guard endSample > startSample else { continue }

            let clip = Array(samples[startSample..<endSample])
            let result = try await Self.transcribeProductPathClip(
                index: index,
                window: window,
                clip: clip,
                service: service
            )
            segmentMetrics.append(result.segmentMetric)
            allReferences.append(window.text)
            allHypotheses.append(result.hypothesis)
            totalDistance += result.segmentMetric.distance
            totalReferenceLength += result.segmentMetric.referenceLength
            totalAudioSeconds += result.audioSeconds
            totalElapsedSeconds += result.elapsedSeconds
            emptyVisibleTranscriptCount += result.emptyVisibleTranscriptCount
            userVisibleFallbackEventCount += result.userVisibleFallbackEventCount
            previewRevisionCount += result.previewRevisionCount
            unstablePartialRatios.append(result.unstablePartialRatio)
            firstVisibleSecondsValues.append(result.firstVisibleSeconds)
            finalDelaySecondsValues.append(result.finalTranscriptDelaySeconds)
        }

        guard !segmentMetrics.isEmpty, totalReferenceLength > 0 else {
            Issue.record("product-path measured window is empty")
            return
        }

        let referenceText = allReferences.joined(separator: " ")
        let hypothesisText = allHypotheses.joined(separator: " ")
        let globalStats = Self.cerStats(reference: referenceText, hypothesis: hypothesisText)
        let microCER = Double(totalDistance) / Double(totalReferenceLength)
        let globalCER = globalStats.refLen > 0 ? Double(globalStats.distance) / Double(globalStats.refLen) : 0
        let firstVisibleSeconds = firstVisibleSecondsValues.min() ?? totalElapsedSeconds
        let finalTranscriptDelaySeconds = Self.average(finalDelaySecondsValues) ?? 0
        let unstablePartialRatio = Self.average(unstablePartialRatios) ?? 0
        let audioSeconds = totalAudioSeconds
        let elapsedSeconds = totalElapsedSeconds
        let rtf = audioSeconds > 0 ? elapsedSeconds / audioSeconds : 0

        let metric = STTBenchmarkRunMetric(
            benchmarkKind: "product_path_final",
            engineID: service.speechEngineID.rawValue,
            engineLabel: engineLabel,
            modelID: service.speechEngineID.whisperVariant == nil ? "" : service.modelVariant,
            sampleID: Self.sampleID,
            supportsPreview: service.supportsPreviewTranscription,
            benchmarkSeconds: audioSeconds,
            totalUnitCount: windows.count,
            measuredUnitCount: segmentMetrics.count,
            referenceLength: totalReferenceLength,
            hypothesisLength: STTBenchmarkTextMetrics.normalizedLength(hypothesisText),
            distance: totalDistance,
            microCER: microCER,
            macroCER: STTBenchmarkTextMetrics.macroCER(segmentMetrics),
            globalDistance: globalStats.distance,
            globalReferenceLength: globalStats.refLen,
            globalCER: globalCER,
            emptyFinalCount: emptyVisibleTranscriptCount,
            audioSeconds: audioSeconds,
            elapsedSeconds: elapsedSeconds,
            rtf: rtf,
            peakMemoryMB: STTBenchmarkProcessMetrics.peakResidentMemoryMB(),
            metadata: [
                "product_path": "true",
                "transcription_route": Self.routeDescription(plan.route),
                "uses_voice_activity_detector": plan.usesVoiceActivityDetector ? "true" : "false",
                "accepts_continuous_audio": plan.acceptsContinuousAudio ? "true" : "false",
                "time_to_first_visible_text_seconds": Self.metricString(firstVisibleSeconds),
                "final_transcript_delay_seconds": Self.metricString(finalTranscriptDelaySeconds),
                "preview_revision_count": "\(previewRevisionCount)",
                "unstable_partial_ratio": Self.metricString(unstablePartialRatio),
                "empty_visible_transcript_count": "\(emptyVisibleTranscriptCount)",
                "permission_asset_failure_count": "0",
                "sidecar_startup_failure_count": "0",
                "cold_start_seconds": Self.metricString(coldStartSeconds),
                "user_visible_fallback_event_count": "\(userVisibleFallbackEventCount)",
                "window_seconds": Self.metricString(Self.windowSeconds),
                "min_window_seconds": Self.metricString(Self.minWindowSeconds),
                "max_gap_seconds": Self.metricString(Self.maxGapSeconds),
                "audio_pad_seconds": Self.metricString(Self.audioPaddingSeconds),
                "max_captions_per_window": "\(Self.maxCaptionsPerWindow)",
            ],
            segments: segmentMetrics
        )

        try Self.writeMetricsIfNeeded(metric)
        print("""
        === Product Path Meeting Corpus [\(engineLabel)] ===
        route: \(Self.routeDescription(plan.route))
        windows: \(segmentMetrics.count)/\(windows.count)
        first_visible_sec: \(String(format: "%.3f", firstVisibleSeconds))
        final_delay_sec: \(String(format: "%.3f", finalTranscriptDelaySeconds))
        CER: \(String(format: "%.1f%%", microCER * 100))
        """)
    }

    @Test("long single SMI caption is split into bounded windows")
    func longSingleSMICaptionSplitsIntoBoundedWindows() {
        let caption = Caption(
            start: 0,
            end: 95,
            cc: (0..<20).map { "word\($0)" }.joined(separator: " ")
        )

        let windows = Self.mergeIntoWindows(
            [caption],
            windowSeconds: 30,
            minWindowSeconds: 0,
            maxCaptionsPerWindow: 0
        )

        #expect(windows.count == 4)
        #expect(windows[0].start == 0)
        #expect(windows[0].end == 30)
        #expect(windows[3].end == 95)
        #expect(windows.allSatisfy { !$0.text.isEmpty })
    }

    private static var drainObservationSeconds: Double {
        nonNegativeDoubleEnv("PRODUCT_PATH_DRAIN_OBSERVE_SECONDS") ?? 0.5
    }

    private static var feedFrameSamples: Int {
        guard let rawValue = ProcessInfo.processInfo.environment["PRODUCT_PATH_FEED_FRAME_SAMPLES"],
              let value = Int(rawValue),
              value > 0 else {
            return 1_600
        }
        return value
    }

    private static func feedSamples(
        _ samples: [Float],
        to audioSource: ProductPathBenchmarkAudioSource,
        observing viewModel: TranscriptionViewModel,
        recorder: ProductPathVisibilityRecorder
    ) async throws {
        var index = 0
        while index < samples.count {
            let end = min(index + Self.feedFrameSamples, samples.count)
            audioSource.emit(samples: Array(samples[index..<end]))
            recorder.observe(viewModel)
            index = end
            if index % (Self.feedFrameSamples * 20) == 0 {
                await Task.yield()
            }
        }
    }

    private static func observe(
        _ viewModel: TranscriptionViewModel,
        recorder: ProductPathVisibilityRecorder,
        seconds: Double
    ) async {
        guard seconds > 0 else { return }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            recorder.observe(viewModel)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func transcribeProductPathClip(
        index: Int,
        window: Window,
        clip: [Float],
        service: STTService
    ) async throws -> ProductPathClipResult {
        let audioSource = ProductPathBenchmarkAudioSource()
        // main의 TranscriptionViewModel은 correctionService를 주입받지 않는다(LLMCorrectionService.shared
        // 내장). 벤치마크 프로세스는 LLM provider 미설정이라 correct()가 nil 반환=no-op이므로
        // 교정이 STT 측정을 오염시키지 않는다(원시 전사만 측정).
        let viewModel = TranscriptionViewModel(
            sttService: service,
            audioSource: audioSource,
            vadProcessor: VoiceActivityDetectorFactory.makeDefault(),
            summaryService: ProductPathNoopSummaryService()
        )
        let recorder = ProductPathVisibilityRecorder()
        let startedAt = Date()
        viewModel.startRecording()
        try await Self.feedSamples(
            clip,
            to: audioSource,
            observing: viewModel,
            recorder: recorder
        )
        await Self.observe(viewModel, recorder: recorder, seconds: Self.drainObservationSeconds)
        await viewModel.stopRecordingAndDrain()
        recorder.observe(viewModel)
        let stoppedAt = Date()
        _ = await viewModel.finalizeMeeting()
        recorder.observe(viewModel)

        let hypothesis = viewModel.committedSegments
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let stats = Self.cerStats(reference: window.text, hypothesis: hypothesis)
        let durationSeconds = window.end - window.start
        let audioSeconds = Double(clip.count) / Double(Self.sampleRate)
        let elapsedSeconds = stoppedAt.timeIntervalSince(startedAt)
        let firstVisibleSeconds = recorder.firstVisibleAt?.timeIntervalSince(startedAt) ?? elapsedSeconds
        let empty = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let segmentMetric = STTBenchmarkSegmentMetric(
            index: index,
            startSeconds: window.start,
            endSeconds: window.end,
            durationSeconds: durationSeconds,
            reference: window.text,
            hypothesis: hypothesis,
            referenceLength: stats.refLen,
            hypothesisLength: STTBenchmarkTextMetrics.normalizedLength(hypothesis),
            distance: stats.distance,
            cer: stats.refLen > 0 ? Double(stats.distance) / Double(stats.refLen) : 0,
            elapsedSeconds: elapsedSeconds,
            rtf: audioSeconds > 0 ? elapsedSeconds / audioSeconds : 0,
            empty: empty
        )
        return ProductPathClipResult(
            segmentMetric: segmentMetric,
            hypothesis: hypothesis,
            audioSeconds: audioSeconds,
            elapsedSeconds: elapsedSeconds,
            firstVisibleSeconds: firstVisibleSeconds,
            finalTranscriptDelaySeconds: max(0, stoppedAt.timeIntervalSince(startedAt) - firstVisibleSeconds),
            previewRevisionCount: recorder.previewRevisionCount,
            unstablePartialRatio: recorder.unstablePartialRatio,
            emptyVisibleTranscriptCount: empty ? 1 : 0,
            userVisibleFallbackEventCount: viewModel.errorMessage == nil ? 0 : 1
        )
    }

    private static func routeDescription(_ route: TranscriptionCoordinatorRoute) -> String {
        switch route {
        case .oneShotVADChunks(let rollingPreview):
            return "oneShotVADChunks(rollingPreview:\(rollingPreview))"
        case .trueStreamingSession:
            return "trueStreamingSession"
        }
    }

    private static func writeEngineUnavailableMarkerIfNeeded(_ state: ModelState) throws -> Bool {
        guard case .failed(let reason) = state,
              let outputDirectory = ProcessInfo.processInfo.environment["MEETING_OUTPUT_DIR"]
                  .flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0) }) else {
            return false
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        // main에는 STTBenchmarkUnavailableMarker struct가 없어 인라인 dict로 marker를 쓴다
        // (러너가 engine unavailable을 식별하는 용도, 스키마는 동일).
        let marker = [
            "engine_id": Self.selectedEngineID,
            "sample_id": Self.sampleID,
            "reason": reason,
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(marker)
        try data.write(to: outputDirectory.appendingPathComponent("\(Self.sampleID)_unavailable.json"))
        return true
    }

    private static func writeMetricsIfNeeded(_ metrics: STTBenchmarkRunMetric) throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["MEETING_OUTPUT_DIR"]
            .flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0) }) else {
            return
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metrics)
        try data.write(to: outputDirectory.appendingPathComponent("\(Self.sampleID)_metrics.json"))
    }

    private static var selectedEngineID: String {
        ProcessInfo.processInfo.environment["STT_ENGINE"] ?? ""
    }

    private static var sampleID: String {
        audioURL
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "_full", with: "")
    }

    private struct SMIDocument: Decodable {
        let smiList: [Caption]
    }

    private struct Caption: Decodable {
        let start: Double
        let end: Double
        let cc: String
    }

    private struct Window {
        let start: Double
        let end: Double
        let text: String
    }

    private struct ProductPathClipResult {
        let segmentMetric: STTBenchmarkSegmentMetric
        let hypothesis: String
        let audioSeconds: Double
        let elapsedSeconds: Double
        let firstVisibleSeconds: Double
        let finalTranscriptDelaySeconds: Double
        let previewRevisionCount: Int
        let unstablePartialRatio: Double
        let emptyVisibleTranscriptCount: Int
        let userVisibleFallbackEventCount: Int
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
            throw NSError(domain: "ProductPathMeeting", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "WAV RIFF header is missing: \(url.path)"
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
            throw NSError(domain: "ProductPathMeeting", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "meeting WAV must be 16kHz mono: \(url.path)"
            ])
        }
        guard let audioFormat, let bitsPerSample, let dataRange else {
            throw NSError(domain: "ProductPathMeeting", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "WAV fmt/data chunk is missing: \(url.path)"
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
            throw NSError(domain: "ProductPathMeeting", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "unsupported WAV format: format=\(audioFormat), bits=\(bitsPerSample)"
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

    private static func nonNegativeIntEnv(_ key: String) -> Int? {
        guard let rawValue = ProcessInfo.processInfo.environment[key],
              let value = Int(rawValue),
              value >= 0 else {
            return nil
        }
        return value
    }

    private static func mergeIntoWindows(_ captions: [Caption], windowSeconds: Double) -> [Window] {
        mergeIntoWindows(
            captions,
            windowSeconds: windowSeconds,
            minWindowSeconds: Self.minWindowSeconds,
            maxCaptionsPerWindow: Self.maxCaptionsPerWindow
        )
    }

    private static func mergeIntoWindows(
        _ captions: [Caption],
        windowSeconds: Double,
        minWindowSeconds: Double,
        maxCaptionsPerWindow: Int
    ) -> [Window] {
        let captions = captions.flatMap {
            Self.splitLongCaption($0, windowSeconds: windowSeconds)
        }
        var windows: [Window] = []
        var bucket: [Caption] = []

        func flush() {
            guard let first = bucket.first, let last = bucket.last else { return }
            let text = bucket
                .map { $0.cc.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
            windows.append(Window(start: first.start, end: last.end, text: text))
            bucket = []
        }

        for caption in captions {
            if let last = bucket.last, caption.start - last.end > Self.maxGapSeconds {
                flush()
            }
            if shouldFlushForCaptionCap(
                bucket: bucket,
                maxCaptionsPerWindow: maxCaptionsPerWindow,
                minWindowSeconds: minWindowSeconds
            ) {
                flush()
            }
            bucket.append(caption)
            if let first = bucket.first, caption.end - first.start >= windowSeconds {
                flush()
            }
        }
        flush()
        return windows
    }

    private static func splitLongCaption(_ caption: Caption, windowSeconds: Double) -> [Caption] {
        let durationSeconds = caption.end - caption.start
        guard windowSeconds > 0, durationSeconds > windowSeconds else {
            return [caption]
        }

        let windowCount = max(1, Int(ceil(durationSeconds / windowSeconds)))
        let words = caption.cc.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count >= windowCount {
            return (0..<windowCount).map { index in
                let wordStart = index * words.count / windowCount
                let wordEnd = (index + 1) * words.count / windowCount
                return Caption(
                    start: caption.start + Double(index) * windowSeconds,
                    end: min(caption.end, caption.start + Double(index + 1) * windowSeconds),
                    cc: words[wordStart..<wordEnd].joined(separator: " ")
                )
            }
        }

        let characters = Array(caption.cc)
        guard characters.count >= windowCount else {
            return [caption]
        }
        return (0..<windowCount).map { index in
            let characterStart = index * characters.count / windowCount
            let characterEnd = (index + 1) * characters.count / windowCount
            return Caption(
                start: caption.start + Double(index) * windowSeconds,
                end: min(caption.end, caption.start + Double(index + 1) * windowSeconds),
                cc: String(characters[characterStart..<characterEnd])
            )
        }
    }

    private static func shouldFlushForCaptionCap(
        bucket: [Caption],
        maxCaptionsPerWindow: Int,
        minWindowSeconds: Double
    ) -> Bool {
        guard maxCaptionsPerWindow > 0,
              bucket.count >= maxCaptionsPerWindow,
              let first = bucket.first,
              let last = bucket.last else {
            return false
        }
        return last.end - first.start >= minWindowSeconds
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func metricString(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}

@MainActor
private final class ProductPathVisibilityRecorder {
    private(set) var firstVisibleAt: Date?
    private(set) var previewRevisionCount = 0
    private var previewObservationCount = 0
    private var lastPendingText = ""

    var unstablePartialRatio: Double {
        guard previewObservationCount > 0 else { return 0 }
        return min(1, Double(previewRevisionCount) / Double(previewObservationCount))
    }

    func observe(_ viewModel: TranscriptionViewModel) {
        let pendingText = viewModel.pendingSegment?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasCommittedText = viewModel.committedSegments.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if firstVisibleAt == nil, !pendingText.isEmpty || hasCommittedText {
            firstVisibleAt = Date()
        }
        guard !pendingText.isEmpty else {
            lastPendingText = ""
            return
        }
        previewObservationCount += 1
        if pendingText != lastPendingText {
            previewRevisionCount += 1
            lastPendingText = pendingText
        }
    }
}

private final class ProductPathBenchmarkAudioSource: AudioSourceProtocol {
    var onBuffer: (@Sendable ([Float]) -> Void)?
    var onError: (@Sendable (AudioSourceError) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var availableDevices: [AudioDevice] = []

    func start() throws {}

    func stop() {}

    func selectDevice(_ device: AudioDevice) throws {}

    func emit(samples: [Float]) {
        onBuffer?(samples)
        onLevel?(Self.level(samples))
    }

    private static func level(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return min(1, samples.reduce(0) { max($0, abs($1)) })
    }
}

@MainActor
private final class ProductPathNoopSummaryService: TranscriptionSummaryGenerating {
    func generateIncremental(correctedBatch: String) async -> String? {
        nil
    }

    func generateFinal(transcript: String) async -> MeetingSummary? {
        nil
    }
}
