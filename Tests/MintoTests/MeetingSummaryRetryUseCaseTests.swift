import Foundation
import Testing
@testable import MintoCore

// MARK: - Stubs

@MainActor
private final class StubRetryGenerator: MeetingSummaryRetryGenerating {
    var receivedTranscript: String?
    var receivedContext: SummaryGenerationContext?
    var lastGenerationFailure: LLMProviderError?
    private let result: MeetingSummary?

    init(result: MeetingSummary? = nil, failure: LLMProviderError? = nil) {
        self.result = result
        self.lastGenerationFailure = failure
    }

    func generateFinal(transcript: String, context: SummaryGenerationContext) async -> MeetingSummary? {
        receivedTranscript = transcript
        receivedContext = context
        return result
    }
}

@MainActor
private final class StubRetryStore: MeetingSummaryRetryStoring {
    var attemptedRecords: [MeetingRecord] = []
    var savedRecords: [MeetingRecord] = []
    var saveResult: MeetingSaveResult = .success

    func save(_ record: MeetingRecord) -> MeetingSaveResult {
        attemptedRecords.append(record)
        if saveResult == .success {
            savedRecords.append(record)
        }
        return saveResult
    }
}

@MainActor
private final class StubRetryCandidateIngester: MeetingSummaryRetryCandidateIngesting {
    var ingestedRecords: [MeetingRecord] = []

    func ingestCandidates(from record: MeetingRecord) {
        ingestedRecords.append(record)
    }
}

// MARK: - Helpers

private func makeSegments(texts: [String], startedAt: Date = Date(timeIntervalSince1970: 1000)) -> [Segment] {
    texts.enumerated().map { index, text in
        Segment(text: text, timestamp: startedAt.addingTimeInterval(Double(index * 60)), duration: 60)
    }
}

private func makePlainRecord(
    transcript: [Segment] = [],
    topic: String = "테스트 회의",
    document: String? = nil
) -> MeetingRecord {
    MeetingRecord(
        title: "테스트",
        startedAt: Date(timeIntervalSince1970: 1000),
        durationSeconds: 60,
        topic: topic,
        summary: MeetingSummary.plain("LLM이 잘 안 됐어요"),
        document: document,
        transcript: transcript
    )
}

private func makeStructuredSummary() -> MeetingSummary {
    MeetingSummary(
        title: "회의 제목",
        leadQuestion: "핵심 질문?",
        leadAnswer: "핵심 답변",
        sections: [MeetingSummary.Section(title: "1. 배경", time: "00:01", points: [])],
        keywords: ["Minto", "STT"],
        decisions: [],
        actionItems: [],
        openQuestions: []
    )
}

// MARK: - isPlainFallback 판별 테스트

@Suite("MeetingSummary.isPlainFallback")
struct MeetingSummaryPlainFallbackTests {

    @Test("plain(_:)으로 만든 요약은 isPlainFallback이 true")
    func plainFallbackDetected() {
        let summary = MeetingSummary.plain("회의가 끝났습니다")
        #expect(summary.isPlainFallback == true)
    }

    @Test("구조화 요약은 isPlainFallback이 false")
    func structuredSummaryNotFallback() {
        let summary = makeStructuredSummary()
        #expect(summary.isPlainFallback == false)
    }

    @Test("leadAnswer만 있고 구조화 필드가 모두 비면 isPlainFallback")
    func leadAnswerOnlyIsPlainFallback() {
        let summary = MeetingSummary(leadAnswer: "요약 내용만 있음")
        #expect(summary.isPlainFallback == true)
    }

    @Test("leadAnswer가 비어 있으면 isPlainFallback이 false (isEmpty와 구분)")
    func emptyLeadAnswerIsNotFallback() {
        let summary = MeetingSummary()
        #expect(summary.isPlainFallback == false)
    }

    @Test("title이 있으면 isPlainFallback이 false")
    func titlePresentNotFallback() {
        let summary = MeetingSummary(title: "회의 제목", leadAnswer: "답변")
        #expect(summary.isPlainFallback == false)
    }

    @Test("keywords가 있으면 isPlainFallback이 false")
    func keywordsPresentNotFallback() {
        let summary = MeetingSummary(leadAnswer: "답변", keywords: ["Minto"])
        #expect(summary.isPlainFallback == false)
    }

    @Test("sections이 있으면 isPlainFallback이 false")
    func sectionsPresentNotFallback() {
        let summary = MeetingSummary(
            leadAnswer: "답변",
            sections: [MeetingSummary.Section(title: "섹션", time: "", points: [])]
        )
        #expect(summary.isPlainFallback == false)
    }
}

// MARK: - RetryUseCase 테스트

@MainActor
@Suite("MeetingSummaryRetryUseCase")
struct MeetingSummaryRetryUseCaseTests {

    @Test("구조화 성공 시 summary 교체 + store 저장 + 후보 추가")
    func retrySuccessUpdatesSummaryAndSaves() async {
        let segments = makeSegments(texts: ["첫 발언", "둘째 발언"])
        let record = makePlainRecord(transcript: segments)
        let structured = makeStructuredSummary()
        let generator = StubRetryGenerator(result: structured)
        let store = StubRetryStore()
        let ingester = StubRetryCandidateIngester()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: ingester,
            glossaryResolver: { _ in "" }
        )

        let result = await useCase.retry(record: record)

        guard case .success(let updated) = result else {
            Issue.record("성공 기대했지만 실패: \(result)")
            return
        }
        #expect(updated.id == record.id)
        #expect(updated.summary == structured)
        #expect(store.savedRecords.count == 1)
        #expect(store.savedRecords[0].summary == structured)
        #expect(ingester.ingestedRecords.count == 1)
        #expect(ingester.ingestedRecords[0].id == record.id)
    }

    @Test("전사가 없으면 LLM 미호출 + 기존 요약 보존 + emptyTranscript 실패")
    func retryWithEmptyTranscriptFails() async {
        let record = makePlainRecord(transcript: [])
        let generator = StubRetryGenerator(result: makeStructuredSummary())
        let store = StubRetryStore()
        let ingester = StubRetryCandidateIngester()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: ingester,
            glossaryResolver: { _ in "" }
        )

        let result = await useCase.retry(record: record)

        guard case .failure(let reason) = result else {
            Issue.record("실패 기대했지만 성공")
            return
        }
        #expect(reason == .emptyTranscript)
        #expect(generator.receivedTranscript == nil)
        #expect(store.savedRecords.isEmpty)
        #expect(ingester.ingestedRecords.isEmpty)
    }

    @Test("LLM이 nil 반환 시 기존 요약 보존 + llmFailed 실패")
    func retryWhenLLMFailsPreservesOriginal() async {
        let segments = makeSegments(texts: ["발언 내용"])
        let record = makePlainRecord(transcript: segments)
        let generator = StubRetryGenerator(result: nil)
        let store = StubRetryStore()
        let ingester = StubRetryCandidateIngester()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: ingester,
            glossaryResolver: { _ in "" }
        )

        let result = await useCase.retry(record: record)

        guard case .failure(let reason) = result else {
            Issue.record("실패 기대했지만 성공")
            return
        }
        #expect(reason == .llmFailed(nil))
        #expect(store.savedRecords.isEmpty)
        #expect(ingester.ingestedRecords.isEmpty)
    }

    @Test("LLM provider 오류가 있으면 재요약 실패 사유에 전달한다")
    func retryPropagatesProviderFailureReason() async {
        let segments = makeSegments(texts: ["발언 내용"])
        let record = makePlainRecord(transcript: segments)
        let generator = StubRetryGenerator(result: nil, failure: .modelUnavailable("qwen2.5:3b"))
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: StubRetryStore(),
            glossaryStore: StubRetryCandidateIngester(),
            glossaryResolver: { _ in "" }
        )

        let result = await useCase.retry(record: record)

        guard case .failure(let reason) = result else {
            Issue.record("실패 기대했지만 성공")
            return
        }
        #expect(reason == .llmFailed(.modelUnavailable("qwen2.5:3b")))
    }

    @Test("재시도 결과가 또 plain fallback이면 교체하지 않고 stillPlainFallback 실패")
    func retryResultStillPlainFallbackIsNotSaved() async {
        let segments = makeSegments(texts: ["발언 내용"])
        let record = makePlainRecord(transcript: segments)
        let anotherPlain = MeetingSummary.plain("여전히 평문")
        let generator = StubRetryGenerator(result: anotherPlain)
        let store = StubRetryStore()
        let ingester = StubRetryCandidateIngester()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: ingester,
            glossaryResolver: { _ in "" }
        )

        let result = await useCase.retry(record: record)

        guard case .failure(let reason) = result else {
            Issue.record("실패 기대했지만 성공")
            return
        }
        #expect(reason == .stillPlainFallback)
        #expect(store.savedRecords.isEmpty)
        #expect(ingester.ingestedRecords.isEmpty)
    }

    @Test("buildTranscript는 첫 세그먼트 기준 상대 MM:SS 포맷을 만든다")
    func buildTranscriptFormatsRelativeTimestamp() {
        let start = Date(timeIntervalSince1970: 1000)
        let segments = [
            Segment(text: "안녕하세요", timestamp: start, duration: 10),
            Segment(text: "반갑습니다", timestamp: start.addingTimeInterval(90), duration: 10),
            Segment(text: "감사합니다", timestamp: start.addingTimeInterval(3661), duration: 10),
        ]

        let transcript = MeetingSummaryRetryUseCase.buildTranscript(from: segments)

        let lines = transcript.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "[00:00] 안녕하세요")
        #expect(lines[1] == "[01:30] 반갑습니다")
        #expect(lines[2] == "[61:01] 감사합니다")
    }

    @Test("retry 호출 시 topic과 주입된 glossary를 context에 전달한다")
    func retryPassesTopicAndGlossaryToContext() async {
        let segments = makeSegments(texts: ["발언"])
        let record = makePlainRecord(transcript: segments, topic: "스프린트 회고")
        let generator = StubRetryGenerator(result: makeStructuredSummary())
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: StubRetryStore(),
            glossaryStore: StubRetryCandidateIngester(),
            glossaryResolver: { topic in "용어: \(topic)" }
        )

        _ = await useCase.retry(record: record)

        #expect(generator.receivedContext?.topic == "스프린트 회고")
        #expect(generator.receivedContext?.glossary == "용어: 스프린트 회고")
        #expect(generator.receivedContext?.document == "")
    }

    @Test("retry 호출 시 저장된 document를 context에 전달한다")
    func retryPassesStoredDocumentToContext() async {
        let segments = makeSegments(texts: ["발언"])
        let record = makePlainRecord(
            transcript: segments,
            topic: "스프린트 회고",
            document: "사전 공유한 회의 자료"
        )
        let generator = StubRetryGenerator(result: makeStructuredSummary())
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: StubRetryStore(),
            glossaryStore: StubRetryCandidateIngester(),
            glossaryResolver: { _ in "" }
        )

        _ = await useCase.retry(record: record)

        #expect(generator.receivedContext?.document == "사전 공유한 회의 자료")
    }

    @Test("retry(record:glossary:)는 주입 glossary를 사용하고 성공 저장 시 snapshot을 갱신한다")
    func retryWithInjectedGlossaryUpdatesSnapshotOnSuccess() async {
        let segments = makeSegments(texts: ["발언"])
        var record = makePlainRecord(transcript: segments, topic: "스프린트 회고")
        record.summaryGlossary = "이전 용어"
        let structured = makeStructuredSummary()
        let generator = StubRetryGenerator(result: structured)
        let store = StubRetryStore()
        let ingester = StubRetryCandidateIngester()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: ingester,
            glossaryResolver: { _ in "자동 용어" }
        )

        let result = await useCase.retry(record: record, glossary: "SwiftUI = UI 프레임워크\nMinto")

        guard case .success(let updated) = result else {
            Issue.record("성공 기대했지만 실패: \(result)")
            return
        }
        #expect(generator.receivedContext?.glossary == "SwiftUI = UI 프레임워크\nMinto")
        #expect(updated.summary == structured)
        #expect(updated.summaryGlossary == "SwiftUI = UI 프레임워크\nMinto")
        #expect(store.savedRecords.first?.summaryGlossary == "SwiftUI = UI 프레임워크\nMinto")
        #expect(ingester.ingestedRecords.first?.summaryGlossary == "SwiftUI = UI 프레임워크\nMinto")
    }

    @Test("retry는 문서 용어를 프롬프트에만 병합하고 snapshot에는 저장하지 않는다")
    func retryMergesDocumentTermsOnlyForPrompt() async {
        let segments = makeSegments(texts: ["발언"])
        let record = makePlainRecord(
            transcript: segments,
            topic: "스프린트 회고",
            document: "VAD dry-run 회의 내용"
        )
        let structured = makeStructuredSummary()
        let generator = StubRetryGenerator(result: structured)
        let store = StubRetryStore()
        let ingester = StubRetryCandidateIngester()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: ingester
        )

        let result = await useCase.retry(record: record, glossary: "STT")

        guard case .success(let updated) = result else {
            Issue.record("성공 기대했지만 실패: \(result)")
            return
        }
        #expect(generator.receivedContext?.glossary.contains("STT") == true)
        #expect(generator.receivedContext?.glossary.contains("VAD") == true)
        #expect(generator.receivedContext?.glossary.contains("dry-run") == true)
        #expect(updated.summaryGlossary == "STT")
        #expect(store.savedRecords.first?.summaryGlossary == "STT")
        #expect(ingester.ingestedRecords.first?.summaryGlossary == "STT")
    }

    @Test("retry(record:glossary:)는 빈 glossary를 nil snapshot으로 저장한다")
    func retryWithEmptyInjectedGlossaryClearsSnapshotOnSuccess() async {
        let segments = makeSegments(texts: ["발언"])
        var record = makePlainRecord(transcript: segments)
        record.summaryGlossary = "이전 용어"
        let generator = StubRetryGenerator(result: makeStructuredSummary())
        let store = StubRetryStore()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: StubRetryCandidateIngester()
        )

        let result = await useCase.retry(record: record, glossary: " \n ")

        guard case .success(let updated) = result else {
            Issue.record("성공 기대했지만 실패: \(result)")
            return
        }
        #expect(generator.receivedContext?.glossary == "")
        #expect(updated.summaryGlossary == nil)
        #expect(store.savedRecords.first?.summaryGlossary == nil)
    }

    @Test("재요약 LLM 실패 시 기존 summary와 snapshot을 저장하지 않는다")
    func retryWithInjectedGlossaryPreservesSnapshotWhenLLMFails() async {
        let segments = makeSegments(texts: ["발언 내용"])
        var record = makePlainRecord(transcript: segments)
        record.summaryGlossary = "이전 용어"
        let generator = StubRetryGenerator(result: nil)
        let store = StubRetryStore()
        let ingester = StubRetryCandidateIngester()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: ingester
        )

        let result = await useCase.retry(record: record, glossary: "새 용어")

        guard case .failure(let reason) = result else {
            Issue.record("실패 기대했지만 성공")
            return
        }
        #expect(reason == .llmFailed(nil))
        #expect(store.attemptedRecords.isEmpty)
        #expect(store.savedRecords.isEmpty)
        #expect(ingester.ingestedRecords.isEmpty)
        #expect(record.summaryGlossary == "이전 용어")
    }

    @Test("store 저장 실패 시 후보 미추가 + saveFailed 반환")
    func retryStoreSaveFailedDoesNotIngestCandidates() async {
        let segments = makeSegments(texts: ["발언 내용"])
        var record = makePlainRecord(transcript: segments)
        record.summaryGlossary = "이전 용어"
        let generator = StubRetryGenerator(result: makeStructuredSummary())
        let store = StubRetryStore()
        store.saveResult = .failed
        let ingester = StubRetryCandidateIngester()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: ingester,
            glossaryResolver: { _ in "" }
        )

        let result = await useCase.retry(record: record)

        guard case .failure(let reason) = result else {
            Issue.record("실패 기대했지만 성공")
            return
        }
        #expect(reason == .saveFailed)
        #expect(store.attemptedRecords.first?.summaryGlossary == nil)
        #expect(store.savedRecords.isEmpty)
        #expect(ingester.ingestedRecords.isEmpty)
        #expect(record.summaryGlossary == "이전 용어")
    }

    @Test("LLM이 빈 JSON {}을 반환하면 isEmpty=true로 거부 + stillPlainFallback")
    func retryEmptyStructuredSummaryIsRejected() async {
        let segments = makeSegments(texts: ["발언 내용"])
        let record = makePlainRecord(transcript: segments)
        // MeetingSummary()는 isEmpty=true, isPlainFallback=false — 두 조건 모두 거부해야 한다
        let emptySummary = MeetingSummary()
        let generator = StubRetryGenerator(result: emptySummary)
        let store = StubRetryStore()
        let ingester = StubRetryCandidateIngester()
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: store,
            glossaryStore: ingester,
            glossaryResolver: { _ in "" }
        )

        let result = await useCase.retry(record: record)

        guard case .failure(let reason) = result else {
            Issue.record("실패 기대했지만 성공")
            return
        }
        #expect(reason == .stillPlainFallback)
        #expect(store.savedRecords.isEmpty)
        #expect(ingester.ingestedRecords.isEmpty)
    }
}
