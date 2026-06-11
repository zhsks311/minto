import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("MeetingFileImportUseCase", .serialized)
struct MeetingFileImportUseCaseTests {
    @Test("파일 샘플을 streaming chunk 전사 후 요약하고 일반 회의로 저장한다")
    func importsFileAsMeetingRecord() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let startedAt = Date(timeIntervalSince1970: 1_000)
        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 48_000), durationSeconds: 3)
        let stt = StubFileImportSTT(texts: ["첫 문장", "둘 문장", "셋 문장"])
        let correction = StubFileImportCorrection()
        let summary = StubFileImportSummary(summary: MeetingSummary(title: "요약 제목", leadAnswer: "정리됨"))
        let store = StubFileImportStore()
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: correction,
            summaryService: summary,
            store: store,
            chunkSeconds: 1,
            now: { startedAt }
        )

        let record = try await useCase.importFile(
            URL(fileURLWithPath: "/tmp/source-meeting.m4a"),
            shouldCorrect: false
        )

        #expect(record.title == "요약 제목")
        #expect(record.topic == "source-meeting")
        #expect(record.startedAt == startedAt)
        #expect(record.durationSeconds == 3)
        #expect(record.transcript.map(\.text) == ["첫 문장", "둘 문장", "셋 문장"])
        #expect(record.transcript.map(\.duration) == [1, 1, 1])
        #expect(record.transcript[1].timestamp == startedAt.addingTimeInterval(1))
        #expect(stt.loadedEngines == [.defaultEngine])
        #expect(stt.transcribedSampleCounts == [16_000, 16_000, 16_000])
        #expect(summary.receivedContext?.topic == "source-meeting")
        #expect(summary.receivedTranscript?.contains("[00:02] 셋 문장") == true)
        #expect(store.savedRecords == [record])
        #expect(useCase.state.stage == .completed)
        #expect(useCase.state.stage.title == "가져오기 완료")
        #expect(useCase.state.detailText == "'요약 제목'이 목록에 추가됐어요.")
        #expect(useCase.state.record == record)
    }

    @Test("파일 가져오기 마커는 시작 시 저장되고 성공 시 제거된다")
    func pendingImportMarkerIsStoredThenRemovedOnSuccess() async throws {
        let defaults = InMemoryUserDefaults()
        resetImportStateForTest(in: defaults)
        defer { resetImportStateForTest(in: defaults) }

        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 16_000), durationSeconds: 1)
        let stt = StubFileImportSTT(texts: ["회의 내용"])
        let store = StubFileImportStore()
        var markerDuringImport: String?
        var runningDuringImport: Bool?
        stt.loadProbe = {
            markerDuringImport = MeetingFileImportUseCase.pendingImportFileName(in: defaults)
            runningDuringImport = MeetingFileImportUseCase.isAnyImportRunning
        }
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: StubFileImportCorrection(),
            summaryService: StubFileImportSummary(summary: MeetingSummary(title: "완료 회의")),
            store: store,
            defaults: defaults
        )

        _ = try await useCase.importFile(URL(fileURLWithPath: "/tmp/source-meeting.m4a"), shouldCorrect: false)

        #expect(markerDuringImport == "source-meeting.m4a")
        #expect(runningDuringImport == true)
        #expect(MeetingFileImportUseCase.pendingImportFileName(in: defaults) == nil)
        #expect(MeetingFileImportUseCase.isAnyImportRunning == false)
    }

    @Test("파일 가져오기 마커는 실패 시 제거된다")
    func pendingImportMarkerIsRemovedOnFailure() async {
        let defaults = InMemoryUserDefaults()
        resetImportStateForTest(in: defaults)
        defer { resetImportStateForTest(in: defaults) }

        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 16_000), durationSeconds: 1)
        let stt = StubFileImportSTT(texts: [""])
        var markerDuringImport: String?
        var runningDuringImport: Bool?
        stt.loadProbe = {
            markerDuringImport = MeetingFileImportUseCase.pendingImportFileName(in: defaults)
            runningDuringImport = MeetingFileImportUseCase.isAnyImportRunning
        }
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: StubFileImportCorrection(),
            summaryService: StubFileImportSummary(),
            store: StubFileImportStore(),
            defaults: defaults
        )

        await #expect(throws: MeetingFileImportError.emptyTranscript) {
            try await useCase.importFile(URL(fileURLWithPath: "/tmp/silent.wav"), shouldCorrect: false)
        }

        #expect(markerDuringImport == "silent.wav")
        #expect(runningDuringImport == true)
        #expect(MeetingFileImportUseCase.pendingImportFileName(in: defaults) == nil)
        #expect(MeetingFileImportUseCase.isAnyImportRunning == false)
    }

    @Test("파일 가져오기 마커는 취소 시 제거된다")
    func pendingImportMarkerIsRemovedOnCancellation() async {
        let defaults = InMemoryUserDefaults()
        resetImportStateForTest(in: defaults)
        defer { resetImportStateForTest(in: defaults) }

        let extractor = StubFileExtractor(cancelImmediately: true)
        let stt = StubFileImportSTT(texts: [])
        var markerDuringImport: String?
        var runningDuringImport: Bool?
        stt.loadProbe = {
            markerDuringImport = MeetingFileImportUseCase.pendingImportFileName(in: defaults)
            runningDuringImport = MeetingFileImportUseCase.isAnyImportRunning
        }
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: StubFileImportCorrection(),
            summaryService: StubFileImportSummary(),
            store: StubFileImportStore(),
            defaults: defaults
        )

        await #expect(throws: CancellationError.self) {
            try await useCase.importFile(URL(fileURLWithPath: "/tmp/cancelled.mp4"), shouldCorrect: false)
        }

        #expect(markerDuringImport == "cancelled.mp4")
        #expect(runningDuringImport == true)
        #expect(MeetingFileImportUseCase.pendingImportFileName(in: defaults) == nil)
        #expect(MeetingFileImportUseCase.isAnyImportRunning == false)
    }

    @Test("시작 시 남은 파일 가져오기 마커를 파일명으로 감지한다")
    func detectsPendingImportMarkerOnLaunch() {
        let defaults = InMemoryUserDefaults()
        resetImportStateForTest(in: defaults)
        defer { resetImportStateForTest(in: defaults) }

        defaults.set("/tmp/interrupted-meeting.mov", forKey: MeetingFileImportUseCase.pendingImportFileNameKey)

        #expect(MeetingFileImportUseCase.pendingImportFileName(in: defaults) == "interrupted-meeting.mov")

        MeetingFileImportUseCase.clearPendingImportMarker(in: defaults)
        #expect(MeetingFileImportUseCase.pendingImportFileName(in: defaults) == nil)
    }

    @Test("파일 가져오기 마커는 쓰기 시점에도 파일명만 저장한다")
    func pendingImportMarkerStoresOnlyFileNameWhenStateHasFullPath() {
        let defaults = InMemoryUserDefaults()
        resetImportStateForTest(in: defaults)
        defer { resetImportStateForTest(in: defaults) }

        let useCase = MeetingFileImportUseCase(defaults: defaults)

        useCase.updatePendingImportMarker(for: MeetingFileImportState(
            stage: .analyzing,
            progress: 0.1,
            fileName: "/Users/local/meetings/interrupted-meeting.mov",
            detailText: "가져오는 중"
        ))

        #expect(defaults.string(forKey: MeetingFileImportUseCase.pendingImportFileNameKey) == "interrupted-meeting.mov")
        #expect(MeetingFileImportUseCase.pendingImportFileName(in: defaults) == "interrupted-meeting.mov")
    }

    @Test("전사 교정이 켜져 있으면 파일 import context로 교정본을 만들고 저장한다")
    func appliesCorrectionBeforeSummaryAndSave() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let startedAt = Date(timeIntervalSince1970: 2_000)
        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 16_000), durationSeconds: 1)
        let stt = StubFileImportSTT(texts: ["raw text"])
        let correction = StubFileImportCorrection(responses: ["corrected text"])
        let summary = StubFileImportSummary(summary: MeetingSummary(leadAnswer: "정리"))
        let store = StubFileImportStore()
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: correction,
            summaryService: summary,
            store: store,
            chunkSeconds: 30,
            now: { startedAt }
        )

        let record = try await useCase.importFile(
            URL(fileURLWithPath: "/tmp/local-review.wav"),
            topic: "파일 회의",
            glossary: "Minto",
            document: "사후 처리 자료",
            shouldCorrect: true
        )

        #expect(correction.calls.map(\.text) == ["raw text"])
        #expect(correction.calls.first?.context.topic == "파일 회의")
        #expect(correction.calls.first?.context.glossary == "Minto")
        #expect(correction.calls.first?.context.document == "사후 처리 자료")
        #expect(record.transcript.map(\.text) == ["corrected text"])
        #expect(summary.receivedTranscript == "[00:00] corrected text")
    }

    @Test("파일 import UI 상태는 교정과 요약 단계를 순서대로 노출한다")
    func exposesCorrectionAndSummaryStagesDuringImport() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let startedAt = Date(timeIntervalSince1970: 3_000)
        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 32_000), durationSeconds: 2)
        let stt = StubFileImportSTT(texts: ["raw first", "raw second"])
        let correction = StubFileImportCorrection(responses: ["corrected first", "corrected second"])
        let summary = StubFileImportSummary(summary: MeetingSummary(title: "정리된 회의", leadAnswer: "요약됨"))
        let store = StubFileImportStore()
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: correction,
            summaryService: summary,
            store: store,
            chunkSeconds: 1,
            now: { startedAt }
        )
        correction.stageProbe = { useCase.state.stage }
        summary.stageProbe = { useCase.state.stage }

        let record = try await useCase.importFile(
            URL(fileURLWithPath: "/tmp/local-llm-pipeline.wav"),
            topic: "Local LLM QA",
            glossary: "Liquibase",
            document: "회의 문맥",
            shouldCorrect: true
        )

        #expect(correction.observedStages == [.correcting, .correcting])
        #expect(summary.observedStages == [.summarizing])
        #expect(record.transcript.map(\.text) == ["corrected first", "corrected second"])
        #expect(summary.receivedTranscript == "[00:00] corrected first\n[00:01] corrected second")
        #expect(useCase.state.stage == .completed)
    }

    @Test("전사 결과가 비어 있으면 저장하지 않고 실패 상태를 남긴다")
    func failsWhenTranscriptIsEmpty() async {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 16_000), durationSeconds: 1)
        let stt = StubFileImportSTT(texts: [""])
        let store = StubFileImportStore()
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: StubFileImportCorrection(),
            summaryService: StubFileImportSummary(),
            store: store
        )

        await #expect(throws: MeetingFileImportError.emptyTranscript) {
            try await useCase.importFile(URL(fileURLWithPath: "/tmp/silent.wav"), shouldCorrect: false)
        }
        #expect(store.savedRecords.isEmpty)
        #expect(useCase.state.stage == .failed)
        #expect(useCase.state.errorMessage == MeetingFileImportError.emptyTranscript.localizedDescription)
    }

    @Test("취소되면 저장하지 않고 cancelled 상태를 남긴다")
    func cancellationDoesNotSavePartialRecord() async {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let extractor = StubFileExtractor(cancelImmediately: true)
        let store = StubFileImportStore()
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: StubFileImportSTT(texts: []),
            correctionService: StubFileImportCorrection(),
            summaryService: StubFileImportSummary(),
            store: store
        )

        await #expect(throws: CancellationError.self) {
            try await useCase.importFile(URL(fileURLWithPath: "/tmp/cancelled.mp4"), shouldCorrect: false)
        }
        #expect(store.savedRecords.isEmpty)
        #expect(useCase.state.stage == .cancelled)
    }

    @Test("chunk 처리 중 취소되어도 부분 회의를 저장하지 않는다")
    func cancellationDuringChunkProcessingDoesNotSavePartialRecord() async {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 16_000), durationSeconds: 1)
        let stt = StubFileImportSTT(texts: [""], cancelOnCall: 1)
        let store = StubFileImportStore()
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: StubFileImportCorrection(),
            summaryService: StubFileImportSummary(),
            store: store
        )

        await #expect(throws: CancellationError.self) {
            try await useCase.importFile(URL(fileURLWithPath: "/tmp/chunk-cancelled.wav"), shouldCorrect: false)
        }
        #expect(store.savedRecords.isEmpty)
        #expect(useCase.state.stage == .cancelled)
    }

    @Test("파일 chunking은 마지막 짧은 구간의 offset과 duration을 보존한다")
    func chunkingPreservesRemainderTiming() {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let chunks = MeetingFileImportUseCase.makeChunks(
            samples: [Float](repeating: 0.1, count: 40_000),
            chunkSeconds: 1,
            sampleRate: 16_000
        )

        #expect(chunks.map(\.samples.count) == [16_000, 16_000, 8_000])
        #expect(chunks.map(\.startSeconds) == [0, 1, 2])
        #expect(chunks.map(\.durationSeconds) == [1, 1, 0.5])
    }

    @Test("지원하지 않는 파일 형식은 읽기 전에 거부한다")
    func rejectsUnsupportedFileType() async {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        await #expect(throws: FileAudioExtractionError.unsupportedFile) {
            _ = try await FileAudioExtractor().extractChunks(
                from: URL(fileURLWithPath: "/tmp/not-a-meeting.txt"),
                chunkSeconds: 1,
                onChunk: { _ in }
            )
        }
    }

    @Test("작은 wav 파일은 실제 AVFoundation extractor를 통해 chunk를 방출한다")
    func extractsSmallWAVFixture() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let url = try makeTempWAV(samples: [Int16](repeating: 600, count: 8_000))
        var chunks: [FileAudioChunk] = []

        let extraction = try await FileAudioExtractor().extractChunks(
            from: url,
            chunkSeconds: 1,
            onChunk: { chunk in
                chunks.append(chunk)
            }
        )

        #expect(extraction.durationSeconds > 0)
        #expect(chunks.count == 1)
        #expect(chunks.first?.samples.isEmpty == false)
        #expect(chunks.first?.startSeconds == 0)
    }

    @Test("실제 extractor는 부모 task 취소를 detached reader에 전파한다")
    func realExtractorCancellationPropagatesToDetachedReader() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let url = try makeTempWAV(samples: [Int16](repeating: 600, count: 32_000))
        let extractionTask = Task {
            try await FileAudioExtractor().extractChunks(
                from: url,
                chunkSeconds: 1,
                onChunk: { _ in
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                }
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        extractionTask.cancel()

        let outcome = await extractionOutcome(for: extractionTask, timeoutNanoseconds: 1_000_000_000)
        #expect(outcome == .cancelled)
    }
}

@MainActor
private func resetImportStateForTest(in defaults: UserDefaults = .standard) {
    MeetingFileImportUseCase.resetImportStateForTesting(in: defaults)
}

private struct StubFileExtractor: MeetingFileAudioExtracting {
    let samples: [Float]
    let durationSeconds: TimeInterval
    let cancelImmediately: Bool

    init(samples: [Float] = [], durationSeconds: TimeInterval = 0, cancelImmediately: Bool = false) {
        self.samples = samples
        self.durationSeconds = durationSeconds
        self.cancelImmediately = cancelImmediately
    }

    func extractChunks(
        from url: URL,
        chunkSeconds: TimeInterval,
        onChunk: @MainActor @Sendable @escaping (FileAudioChunk) async throws -> Void
    ) async throws -> FileAudioExtraction {
        if cancelImmediately { throw CancellationError() }
        for chunk in FileAudioExtractor.makeChunks(
            samples: samples,
            chunkSeconds: chunkSeconds,
            sampleRate: STTAudioUtilities.sampleRate
        ) {
            try await onChunk(chunk)
        }
        return FileAudioExtraction(durationSeconds: durationSeconds)
    }
}

@MainActor
private final class StubFileImportSTT: MeetingFileImportSTTServicing {
    var modelState: ModelState = .unloaded
    var loadedEngines: [SpeechEngineID] = []
    var transcribedSampleCounts: [Int] = []
    var loadProbe: (@MainActor () -> Void)?
    private var texts: [String]
    private let cancelOnCall: Int?

    init(texts: [String], cancelOnCall: Int? = nil) {
        self.texts = texts
        self.cancelOnCall = cancelOnCall
    }

    func loadEngine(_ engineID: SpeechEngineID) async {
        loadedEngines.append(engineID)
        modelState = .loaded
        loadProbe?()
    }

    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        transcribedSampleCounts.append(pcmSamples.count)
        if transcribedSampleCounts.count == cancelOnCall {
            throw CancellationError()
        }
        let text = texts.isEmpty ? "" : texts.removeFirst()
        return TranscriptionResult(
            segment: Segment(text: text, timestamp: Date(), duration: Double(pcmSamples.count) / 16_000),
            isFinal: true
        )
    }
}

@MainActor
private final class StubFileImportCorrection: MeetingFileImportCorrecting {
    struct Call: Equatable {
        let text: String
        let context: LLMCorrectionContext
    }

    var calls: [Call] = []
    var observedStages: [MeetingFileImportStage] = []
    var stageProbe: (@MainActor () -> MeetingFileImportStage)?
    private var responses: [String?]

    init(responses: [String?] = []) {
        self.responses = responses
    }

    func correct(text: String, context: LLMCorrectionContext) async -> String? {
        if let stageProbe {
            observedStages.append(stageProbe())
        }
        calls.append(Call(text: text, context: context))
        return responses.isEmpty ? nil : responses.removeFirst()
    }
}

@MainActor
private final class StubFileImportSummary: MeetingFileImportSummaryGenerating {
    var receivedTranscript: String?
    var receivedContext: SummaryGenerationContext?
    var observedStages: [MeetingFileImportStage] = []
    var stageProbe: (@MainActor () -> MeetingFileImportStage)?
    private let summary: MeetingSummary?

    init(summary: MeetingSummary? = nil) {
        self.summary = summary
    }

    func generateFinal(transcript: String, context: SummaryGenerationContext) async -> MeetingSummary? {
        if let stageProbe {
            observedStages.append(stageProbe())
        }
        receivedTranscript = transcript
        receivedContext = context
        return summary
    }
}

@MainActor
private final class StubFileImportStore: MeetingFileImportStoring {
    var savedRecords: [MeetingRecord] = []
    var shouldSave = true

    func save(_ record: MeetingRecord) -> MeetingSaveResult {
        guard shouldSave else { return .failed }
        savedRecords.append(record)
        return .success
    }
}

private enum ExtractionTaskOutcome: Equatable {
    case cancelled
    case completed
    case failed
    case timedOut
}

private func extractionOutcome(
    for task: Task<FileAudioExtraction, Error>,
    timeoutNanoseconds: UInt64
) async -> ExtractionTaskOutcome {
    await withTaskGroup(of: ExtractionTaskOutcome.self) { group in
        group.addTask {
            do {
                _ = try await task.value
                return .completed
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed
            }
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return .timedOut
        }
        let outcome = await group.next() ?? .timedOut
        group.cancelAll()
        return outcome
    }
}

private func makeTempWAV(samples: [Int16], sampleRate: Int = 16_000) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("minto-file-import-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("fixture.wav")
    try makeWAVData(samples: samples, sampleRate: sampleRate).write(to: url)
    return url
}

private func makeWAVData(samples: [Int16], sampleRate: Int) -> Data {
    var data = Data()
    let bytesPerSample = 2
    let dataByteCount = UInt32(samples.count * bytesPerSample)
    appendASCII("RIFF", to: &data)
    appendLittleEndian(UInt32(36) + dataByteCount, to: &data)
    appendASCII("WAVE", to: &data)
    appendASCII("fmt ", to: &data)
    appendLittleEndian(UInt32(16), to: &data)
    appendLittleEndian(UInt16(1), to: &data)
    appendLittleEndian(UInt16(1), to: &data)
    appendLittleEndian(UInt32(sampleRate), to: &data)
    appendLittleEndian(UInt32(sampleRate * bytesPerSample), to: &data)
    appendLittleEndian(UInt16(bytesPerSample), to: &data)
    appendLittleEndian(UInt16(16), to: &data)
    appendASCII("data", to: &data)
    appendLittleEndian(dataByteCount, to: &data)
    for sample in samples {
        appendLittleEndian(UInt16(bitPattern: sample), to: &data)
    }
    return data
}

private func appendASCII(_ string: String, to data: inout Data) {
    data.append(contentsOf: string.utf8)
}

private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { bytes in
        data.append(contentsOf: bytes)
    }
}

// MARK: - FileAudioExtractionError 사용자 메시지 매핑 테스트

@Suite("FileAudioExtractionError 사용자 메시지")
struct FileAudioExtractionErrorMessageTests {
    @Test("unsupportedFile → 형식 안내 메시지")
    func unsupportedFileMessage() {
        let error = FileAudioExtractionError.unsupportedFile
        #expect(error.errorDescription == "지원하지 않는 파일 형식이에요. 오디오 파일이나 mp4/mov 영상을 선택해 주세요.")
    }

    @Test("noAudioTrack → 오디오 트랙 없음 메시지")
    func noAudioTrackMessage() {
        let error = FileAudioExtractionError.noAudioTrack
        #expect(error.errorDescription == "이 파일에는 오디오 트랙이 없어요.")
    }

    @Test("noReadableAudio → 손상 가능성 메시지")
    func noReadableAudioMessage() {
        let error = FileAudioExtractionError.noReadableAudio
        #expect(error.errorDescription == "오디오를 읽지 못했어요. 파일이 손상됐을 수 있어요.")
    }

    @Test("invalidAudioFormat → 처리 불가 메시지")
    func invalidAudioFormatMessage() {
        let error = FileAudioExtractionError.invalidAudioFormat
        #expect(error.errorDescription == "파일 음성 포맷을 처리할 수 없어요.")
    }

    @Test("readerFailed → 시스템 원인 병기 메시지")
    func readerFailedMessage() {
        let error = FileAudioExtractionError.readerFailed("Cannot Open")
        let description = error.errorDescription ?? ""
        #expect(description.hasPrefix("파일을 열 수 없어요. 손상되었거나 지원하지 않는 코덱일 수 있어요."))
        #expect(description.contains("Cannot Open"))
    }

    @Test("readerFailed localizedDescription은 errorDescription과 일치한다")
    func readerFailedLocalized() {
        let error = FileAudioExtractionError.readerFailed("Cannot Open")
        #expect(error.localizedDescription == error.errorDescription)
    }

    @Test("텍스트 내용의 가짜 mp4 파일은 readerFailed 또는 noAudioTrack을 throw하고 한글 안내를 반환한다")
    func fakeMP4ThrowsFileAudioExtractionErrorWithKoreanMessage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-fake-mp4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fake.mp4")
        try Data("not a real mp4 file".utf8).write(to: url)

        do {
            _ = try await FileAudioExtractor().extractChunks(from: url, chunkSeconds: 1, onChunk: { _ in })
            Issue.record("예외가 발생하지 않았습니다.")
        } catch let error as FileAudioExtractionError {
            switch error {
            case .readerFailed(let message):
                let description = error.errorDescription ?? ""
                #expect(description.hasPrefix("파일을 열 수 없어요."))
                #expect(!message.isEmpty)
            case .noAudioTrack:
                #expect(error.errorDescription == "이 파일에는 오디오 트랙이 없어요.")
            default:
                Issue.record("예상치 못한 FileAudioExtractionError: \(error)")
            }
        } catch {
            Issue.record("FileAudioExtractionError가 아닌 에러: \(error)")
        }
    }
}
