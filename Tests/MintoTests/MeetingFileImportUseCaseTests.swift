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

    @Test("파일 import 교정은 전사와 겹쳐 돌고 요약 전에 모두 반영된다")
    func exposesCorrectionAndSummaryStagesDuringImport() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let startedAt = Date(timeIntervalSince1970: 3_000)
        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 32_000), durationSeconds: 2)
        let stt = StubFileImportSTT(texts: ["raw first", "raw second"])
        let correction = StubFileImportCorrection()
        correction.responseByText = [
            "raw first": "corrected first",
            "raw second": "corrected second",
        ]
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

        // 교정은 추출 중(transcribing) 백그라운드로 시작되거나 추출 후 drain(correcting)에서 돈다.
        #expect(correction.observedStages.count == 2)
        #expect(correction.observedStages.allSatisfy { $0 == .transcribing || $0 == .correcting })
        #expect(summary.observedStages == [.summarizing])
        #expect(record.transcript.map(\.text) == ["corrected first", "corrected second"])
        #expect(summary.receivedTranscript == "[00:00] corrected first\n[00:01] corrected second")
        #expect(useCase.state.stage == .completed)
    }

    @Test("교정이 청크 순서와 다르게 끝나도 transcript 순서는 보존된다")
    func preservesChunkOrderWhenCorrectionsFinishOutOfOrder() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let startedAt = Date(timeIntervalSince1970: 4_000)
        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 32_000), durationSeconds: 2)
        let stt = StubFileImportSTT(texts: ["raw first", "raw second"])
        let correction = StubFileImportCorrection()
        correction.responseByText = [
            "raw first": "corrected first",
            "raw second": "corrected second",
        ]
        correction.delayNanosecondsByText = [
            "raw first": 200_000_000,
            "raw second": 10_000_000,
        ]
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: correction,
            summaryService: StubFileImportSummary(summary: MeetingSummary(title: "순서 보존")),
            store: StubFileImportStore(),
            chunkSeconds: 1,
            now: { startedAt }
        )

        let record = try await useCase.importFile(
            URL(fileURLWithPath: "/tmp/out-of-order.wav"),
            shouldCorrect: true
        )

        #expect(record.transcript.map(\.text) == ["corrected first", "corrected second"])
        #expect(record.transcript[0].timestamp == startedAt)
        #expect(record.transcript[1].timestamp == startedAt.addingTimeInterval(1))
    }

    @Test("동시 교정은 주입한 상한을 넘지 않는다")
    func limitsConcurrentCorrections() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 64_000), durationSeconds: 4)
        let stt = StubFileImportSTT(texts: ["one", "two", "three", "four"])
        let correction = StubFileImportCorrection()
        correction.defaultDelayNanoseconds = 50_000_000
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: correction,
            summaryService: StubFileImportSummary(summary: MeetingSummary(title: "상한")),
            store: StubFileImportStore(),
            chunkSeconds: 1,
            maxConcurrentCorrections: 2
        )

        _ = try await useCase.importFile(
            URL(fileURLWithPath: "/tmp/concurrency-cap.wav"),
            shouldCorrect: true
        )

        #expect(correction.calls.count == 4)
        #expect(correction.maxActiveCorrections == 2)
    }

    @Test("교정 실패(nil)는 해당 청크만 원문으로 남긴다")
    func correctionNilFallsBackToRawTextPerChunk() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 32_000), durationSeconds: 2)
        let stt = StubFileImportSTT(texts: ["raw first", "raw second"])
        let correction = StubFileImportCorrection()
        correction.responseByText = [
            "raw first": "corrected first",
            "raw second": String?.none,
        ]
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: correction,
            summaryService: StubFileImportSummary(summary: MeetingSummary(title: "fail-soft")),
            store: StubFileImportStore(),
            chunkSeconds: 1
        )

        let record = try await useCase.importFile(
            URL(fileURLWithPath: "/tmp/fail-soft.wav"),
            shouldCorrect: true
        )

        #expect(record.transcript.map(\.text) == ["corrected first", "raw second"])
    }

    @Test("배치 교정 문맥은 배치 첫 청크 직전의 원문들로 구성된다")
    func correctionContextUsesPreviousRawTextsAtBatchBoundary() async throws {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        // 5청크 → 배치 3+2. 배치 안 청크들은 같은 프롬프트의 번호 목록으로 서로를
        // 직접 보므로, previousText 문맥은 배치 첫 청크 기준 스냅샷이면 충분하다.
        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 80_000), durationSeconds: 5)
        let stt = StubFileImportSTT(texts: ["raw one", "raw two", "raw three", "raw four", "raw five"])
        let correction = StubFileImportCorrection()
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: correction,
            summaryService: StubFileImportSummary(summary: MeetingSummary(title: "문맥")),
            store: StubFileImportStore(),
            chunkSeconds: 1
        )

        _ = try await useCase.importFile(
            URL(fileURLWithPath: "/tmp/raw-context.wav"),
            shouldCorrect: true
        )

        #expect(correction.batchCalls.count == 2)
        #expect(correction.batchCalls.first?.texts == ["raw one", "raw two", "raw three"])
        #expect(correction.batchCalls.first?.context.previousText == "")
        #expect(correction.batchCalls.last?.texts == ["raw four", "raw five"])
        #expect(correction.batchCalls.last?.context.previousText == "raw one\nraw two\nraw three")
    }

    @Test("교정 drain 중 취소되면 저장하지 않고 cancelled 상태를 남긴다")
    func cancellationDuringCorrectionDrainDoesNotSave() async {
        resetImportStateForTest()
        defer { resetImportStateForTest() }

        let extractor = StubFileExtractor(samples: [Float](repeating: 0.2, count: 32_000), durationSeconds: 2)
        let stt = StubFileImportSTT(texts: ["raw first", "raw second"])
        let correction = StubFileImportCorrection()
        correction.defaultDelayNanoseconds = 10_000_000_000
        let store = StubFileImportStore()
        let useCase = MeetingFileImportUseCase(
            extractor: extractor,
            sttService: stt,
            correctionService: correction,
            summaryService: StubFileImportSummary(summary: MeetingSummary(title: "취소")),
            store: store,
            chunkSeconds: 1
        )

        let importTask = Task {
            try await useCase.importFile(
                URL(fileURLWithPath: "/tmp/drain-cancel.wav"),
                shouldCorrect: true
            )
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        importTask.cancel()

        let cancelled = await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                do {
                    _ = try await importTask.value
                    return false
                } catch is CancellationError {
                    return true
                } catch {
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let outcome = await group.next() ?? nil
            group.cancelAll()
            return outcome
        }

        #expect(cancelled == true)
        #expect(store.savedRecords.isEmpty)
        #expect(useCase.state.stage == .cancelled)
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
    /// 교정이 병렬로 돌면 호출 순서가 비결정적이라, 순서 의존 큐 대신 입력 텍스트로 응답을 매핑한다.
    var responseByText: [String: String?] = [:]
    var delayNanosecondsByText: [String: UInt64] = [:]
    var defaultDelayNanoseconds: UInt64 = 0
    private(set) var maxActiveCorrections = 0
    private var activeCorrections = 0
    private var responses: [String?]

    init(responses: [String?] = []) {
        self.responses = responses
    }

    func correct(text: String, context: LLMCorrectionContext) async -> String? {
        if let stageProbe {
            observedStages.append(stageProbe())
        }
        calls.append(Call(text: text, context: context))
        activeCorrections += 1
        maxActiveCorrections = max(maxActiveCorrections, activeCorrections)
        defer { activeCorrections -= 1 }
        let delay = delayNanosecondsByText[text] ?? defaultDelayNanoseconds
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        if let mapped = responseByText[text] {
            return mapped
        }
        return responses.isEmpty ? nil : responses.removeFirst()
    }

    struct BatchCall: Equatable {
        let texts: [String]
        let context: LLMCorrectionContext
    }

    private(set) var batchCalls: [BatchCall] = []

    func correctBatch(texts: [String], context: LLMCorrectionContext) async -> [String?]? {
        batchCalls.append(BatchCall(texts: texts, context: context))
        if let stageProbe {
            for _ in texts {
                observedStages.append(stageProbe())
            }
        }
        var results: [String?] = []
        for text in texts {
            activeCorrections += 1
            maxActiveCorrections = max(maxActiveCorrections, activeCorrections)
            let delay = delayNanosecondsByText[text] ?? defaultDelayNanoseconds
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            let result: String?
            if let mapped = responseByText[text] {
                result = mapped
            } else {
                result = responses.isEmpty ? nil : responses.removeFirst()
            }
            activeCorrections -= 1
            results.append(result)
        }
        calls.append(contentsOf: texts.map { Call(text: $0, context: context) })
        return results
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

// MARK: - ImportCorrectionPipeline 단위 테스트

/// 교정 호출을 외부에서 열어줄 때까지 막아두는 게이트 스텁.
/// limiter의 동시 진입·대기자 wake를 suspension 경계에서 직접 관찰한다.
@MainActor
private final class GateFileImportCorrection: MeetingFileImportCorrecting {
    private(set) var enteredCount = 0
    private var gates: [CheckedContinuation<Void, Never>] = []

    func correct(text: String, context: LLMCorrectionContext) async -> String? {
        enteredCount += 1
        await withCheckedContinuation { gates.append($0) }
        return "done \(text)"
    }

    func correctBatch(texts: [String], context: LLMCorrectionContext) async -> [String?]? {
        // gate stub: 배치를 단건처럼 직렬로 처리해 limiter 동작을 그대로 관찰한다
        var results: [String?] = []
        for text in texts {
            let result = await correct(text: text, context: context)
            results.append(result)
        }
        return results
    }

    func releaseAll() {
        let pending = gates
        gates.removeAll()
        for gate in pending {
            gate.resume()
        }
    }
}

@MainActor
@Suite("ImportCorrectionPipeline", .serialized)
struct ImportCorrectionPipelineTests {
    private func dispatchCorrections(
        count: Int,
        into pipeline: ImportCorrectionPipeline,
        using service: GateFileImportCorrection
    ) {
        for index in 0..<count {
            let raw = "raw \(index)"
            let segmentIndex = pipeline.appendRaw(Segment(text: raw, timestamp: Date(), duration: 1))
            pipeline.dispatchCorrection(
                at: segmentIndex,
                rawText: raw,
                context: LLMCorrectionContext(),
                using: service
            )
        }
    }

    /// 조건이 참이 될 때까지 양보한다. 조건 미충족이어도 유한 반복이라 suite가 멈추지 않는다.
    private func yieldUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test("limiter는 동시 진입을 상한으로 막고 해제 시 대기자가 slot을 이어받는다")
    func limiterCapsConcurrentEntries() async {
        let pipeline = ImportCorrectionPipeline(maxConcurrent: 2)
        let gate = GateFileImportCorrection()
        dispatchCorrections(count: 4, into: pipeline, using: gate)

        await yieldUntil { gate.enteredCount == 2 }
        for _ in 0..<50 { await Task.yield() }
        #expect(gate.enteredCount == 2)

        gate.releaseAll()
        await yieldUntil { gate.enteredCount == 4 }
        #expect(gate.enteredCount == 4)
        gate.releaseAll()

        await pipeline.drain { _, _ in }
        #expect(pipeline.correctedCount == 4)
        #expect(pipeline.segments.map(\.text) == ["done raw 0", "done raw 1", "done raw 2", "done raw 3"])
    }

    // MARK: - 배치 파이프라인 테스트

    @Test("7청크는 배치 3+3+1로 디스패치된다")
    func sevenChunksDispatchedAsThreeBatches() async {
        let pipeline = ImportCorrectionPipeline(maxConcurrent: 3)
        let correction = StubFileImportCorrection()
        correction.responseByText = Dictionary(
            uniqueKeysWithValues: (0..<7).map { ("raw \($0)", "corrected \($0)") }
        )
        let context = LLMCorrectionContext()

        for i in 0..<7 {
            let segment = Segment(text: "raw \(i)", timestamp: Date(), duration: 1)
            pipeline.appendRawAndEnqueue(segment, context: context, using: correction)
        }
        pipeline.flushBatchBuffer(using: correction)

        await pipeline.drain { _, _ in }

        #expect(correction.batchCalls.count == 3)
        #expect(correction.batchCalls[0].texts.count == 3)
        #expect(correction.batchCalls[1].texts.count == 3)
        #expect(correction.batchCalls[2].texts.count == 1)
        #expect(pipeline.segments.map(\.text) == (0..<7).map { "corrected \($0)" })
    }

    @Test("배치 중 하나 파싱 실패 시 그 배치만 원문을 유지한다")
    func batchParseFailureKeepsRawTextForThatBatch() async {
        let pipeline = ImportCorrectionPipeline(maxConcurrent: 3)
        // 첫 배치(0,1,2)는 성공, 두 번째 배치(3,4,5)는 nil(파싱 실패)
        // 별도 stub을 인라인으로 만든다.
        final class PartialFailBatchCorrection: MeetingFileImportCorrecting {
            private(set) var batchCount = 0
            func correct(text: String, context: LLMCorrectionContext) async -> String? { nil }
            func correctBatch(texts: [String], context: LLMCorrectionContext) async -> [String?]? {
                batchCount += 1
                if batchCount == 2 {
                    // 두 번째 배치는 파싱 실패를 시뮬레이션
                    return nil
                }
                return texts.map { "ok_\($0)" }
            }
        }
        let service = PartialFailBatchCorrection()
        let ctx = LLMCorrectionContext()

        for i in 0..<6 {
            let segment = Segment(text: "raw \(i)", timestamp: Date(), duration: 1)
            pipeline.appendRawAndEnqueue(segment, context: ctx, batchSize: 3, using: service)
        }
        pipeline.flushBatchBuffer(using: service)

        await pipeline.drain { _, _ in }

        // 첫 배치(0-2): 교정됨
        #expect(pipeline.segments[0].text == "ok_raw 0")
        #expect(pipeline.segments[1].text == "ok_raw 1")
        #expect(pipeline.segments[2].text == "ok_raw 2")
        // 두 번째 배치(3-5): 원문 유지
        #expect(pipeline.segments[3].text == "raw 3")
        #expect(pipeline.segments[4].text == "raw 4")
        #expect(pipeline.segments[5].text == "raw 5")
        #expect(pipeline.correctedCount == 3)
        #expect(pipeline.fallbackCount == 3)
    }

    @Test("배치 파이프라인에서 순서가 보존된다")
    func batchPipelinePreservesOrder() async {
        let pipeline = ImportCorrectionPipeline(maxConcurrent: 3)
        let correction = StubFileImportCorrection()
        correction.responseByText = Dictionary(
            uniqueKeysWithValues: (0..<5).map { ("raw \($0)", "corrected \($0)") }
        )
        // 두 번째 배치(인덱스 3,4)에 지연을 줘 순서 역전 가능성 유발
        correction.delayNanosecondsByText = ["raw 3": 50_000_000]
        let ctx = LLMCorrectionContext()

        for i in 0..<5 {
            let segment = Segment(text: "raw \(i)", timestamp: Date(), duration: 1)
            pipeline.appendRawAndEnqueue(segment, context: ctx, batchSize: 3, using: correction)
        }
        pipeline.flushBatchBuffer(using: correction)

        await pipeline.drain { _, _ in }

        #expect(pipeline.segments.map(\.text) == ["corrected 0", "corrected 1", "corrected 2", "corrected 3", "corrected 4"])
    }

    @Test("배치 파이프라인 취소는 대기 task를 즉시 깨운다")
    func batchPipelineCancellationWakesWaiters() async {
        let pipeline = ImportCorrectionPipeline(maxConcurrent: 1)
        let gate = GateFileImportCorrection()
        let ctx = LLMCorrectionContext()

        // 배치 2개: 첫 배치가 gate에서 막히고 두 번째는 slot 대기
        for i in 0..<6 {
            let segment = Segment(text: "raw \(i)", timestamp: Date(), duration: 1)
            pipeline.appendRawAndEnqueue(segment, context: ctx, batchSize: 3, using: gate)
        }
        pipeline.flushBatchBuffer(using: gate)

        // 첫 배치가 gate 진입할 때까지 대기
        await yieldUntil { gate.enteredCount >= 1 }

        pipeline.cancelPendingCorrections()
        // gate 스텁의 correctBatch는 텍스트마다 gate를 기다리므로(배치 3 = gate 3회)
        // 한 번의 releaseAll로는 첫 배치가 끝나지 않는다 — 전부 끝날 때까지 반복 release.
        await yieldUntil {
            gate.releaseAll()
            return pipeline.correctedCount + pipeline.fallbackCount >= 6
        }

        await pipeline.drain { _, _ in }
        // slot 대기 중이던 두 번째 배치는 service 진입 없이 fallback으로 깨어난다.
        #expect(pipeline.fallbackCount == 3)
        #expect(gate.enteredCount == 3)
    }

    @Test("취소는 slot 대기자를 즉시 깨워 service 진입 없이 fallback으로 끝낸다")
    func cancellationWakesSlotWaiters() async {
        let pipeline = ImportCorrectionPipeline(maxConcurrent: 1)
        let gate = GateFileImportCorrection()
        dispatchCorrections(count: 2, into: pipeline, using: gate)

        await yieldUntil { gate.enteredCount == 1 }
        #expect(gate.enteredCount == 1)

        pipeline.cancelPendingCorrections()
        await yieldUntil { pipeline.fallbackCount == 1 }
        #expect(pipeline.fallbackCount == 1)
        #expect(gate.enteredCount == 1)

        gate.releaseAll()
        await pipeline.drain { _, _ in }
        #expect(pipeline.segments[1].text == "raw 1")
    }
}
