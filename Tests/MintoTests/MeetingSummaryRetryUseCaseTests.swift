import Foundation
import Testing
@testable import MintoCore

// MARK: - Stubs

@MainActor
private final class StubRetryGenerator: MeetingSummaryRetryGenerating {
    var receivedTranscript: String?
    var receivedContext: SummaryGenerationContext?
    private let result: MeetingSummary?

    init(result: MeetingSummary? = nil) {
        self.result = result
    }

    func generateFinal(transcript: String, context: SummaryGenerationContext) async -> MeetingSummary? {
        receivedTranscript = transcript
        receivedContext = context
        return result
    }
}

@MainActor
private final class StubRetryStore: MeetingSummaryRetryStoring {
    var savedRecords: [MeetingRecord] = []

    func save(_ record: MeetingRecord) -> MeetingSaveResult {
        savedRecords.append(record)
        return .success
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

private func makePlainRecord(transcript: [Segment] = [], topic: String = "테스트 회의") -> MeetingRecord {
    MeetingRecord(
        title: "테스트",
        startedAt: Date(timeIntervalSince1970: 1000),
        durationSeconds: 60,
        topic: topic,
        summary: MeetingSummary.plain("LLM이 잘 안 됐어요"),
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
            glossaryStore: ingester
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
            glossaryStore: ingester
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
            glossaryStore: ingester
        )

        let result = await useCase.retry(record: record)

        guard case .failure(let reason) = result else {
            Issue.record("실패 기대했지만 성공")
            return
        }
        #expect(reason == .llmFailed)
        #expect(store.savedRecords.isEmpty)
        #expect(ingester.ingestedRecords.isEmpty)
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
            glossaryStore: ingester
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

    @Test("retry 호출 시 topic을 context에 전달한다")
    func retryPassesTopicToContext() async {
        let segments = makeSegments(texts: ["발언"])
        let record = makePlainRecord(transcript: segments, topic: "스프린트 회고")
        let generator = StubRetryGenerator(result: makeStructuredSummary())
        let useCase = MeetingSummaryRetryUseCase(
            summaryService: generator,
            store: StubRetryStore(),
            glossaryStore: StubRetryCandidateIngester()
        )

        _ = await useCase.retry(record: record)

        #expect(generator.receivedContext?.topic == "스프린트 회고")
        #expect(generator.receivedContext?.glossary == "")
        #expect(generator.receivedContext?.document == "")
    }
}
