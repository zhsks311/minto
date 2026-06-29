import os
import Foundation
import Combine

/// 현재 녹음 세션의 회의 맥락(주제 + 용어집).
///
/// 회의마다 "녹음 시작" 시트에서 새로 입력받는 **세션 단위 in-memory 상태**다.
/// 영구 저장(@AppStorage)하지 않으므로 지난 회의 맥락이 다음 회의로 새지 않는다.
/// 현재는 LLM 후교정에만 쓰이지만, 향후 요약/문서/실시간 검색 기능이 공유·확장할 토대다.
@MainActor
public final class MeetingContext: ObservableObject {

    public static let shared = MeetingContext()
    private init() {}

    private var documentTermExtractionID: UUID?
    private var documentSummaryGenerationID: UUID?

    /// 회의 주제·배경·참석자 등 자유 텍스트.
    @Published public var topic: String = ""

    /// 고유명사·전문용어 목록 (줄 단위).
    @Published public var glossary: String = ""

    /// 회의 안건/문서(선택). 주어지면 교정·요약 프롬프트에 참고자료로 주입해 품질을 올린다.
    @Published public var document: String = ""

    /// 매칭된 캘린더 이벤트 식별자. 세션 동안만 보관하고 저장 시 MeetingRecord로 넘긴다.
    @Published public var calendarEventIdentifier: String?

    /// 첨부 문서에서 정적으로 추출한 이번 회의용 용어. 영구 저장하지 않는다.
    @Published public var documentTerms: [String] = []

    /// 첨부 문서를 회의 시작 시 1회 LLM으로 압축한 요약본(요약 프롬프트 참고 맥락). 영구 저장하지 않는다.
    /// 생성 전·실패 시 nil이며, 그 경우 요약 프롬프트는 excerpt 폴백으로 동작한다(fail-soft).
    @Published public var documentSummary: String?

    /// 회의 진행 중 누적되는 요약(증분 갱신). 교정 context로도 쓰이고, 종료 시 최종 요약의 입력이 된다.
    @Published public var runningSummary: String = ""

    /// 회의 종료 시 정제된 **구조화** 최종 요약(사용자에게 표시).
    @Published public var finalSummary: MeetingSummary?

    /// 교정에 쓸 맥락이 하나라도 있는지.
    public var hasContext: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !glossary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 프롬프트에 넣을 용어집. 사용자 입력 glossary 뒤에 이미 추출된 문서 용어를 줄 단위로 병합한다.
    public var glossaryForPrompt: String {
        guard !documentTerms.isEmpty else { return glossary }

        let userLines = DocumentTermExtractor.glossaryLines(from: glossary)
        var existingKeys = DocumentTermExtractor.existingComparableKeys(from: userLines)

        var mergedLines = userLines
        for term in documentTerms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = DocumentTermExtractor.comparableText(trimmed)
            guard !key.isEmpty, !existingKeys.contains(key) else { continue }
            existingKeys.insert(key)
            mergedLines.append(trimmed)
        }

        guard mergedLines.count != userLines.count else { return glossary }
        return mergedLines.joined(separator: "\n")
    }

    /// 새 회의 세션 시작 시 호출. 지정값으로 교체하고 이전 회의의 요약은 비운다(세션 간 누수 방지).
    public func start(
        topic: String,
        glossary: String,
        document: String = "",
        calendarEventIdentifier: String? = nil
    ) {
        self.topic = topic
        self.glossary = glossary
        self.document = document
        self.calendarEventIdentifier = calendarEventIdentifier
        self.documentTerms = []
        self.documentTermExtractionID = nil
        self.documentSummary = nil
        self.documentSummaryGenerationID = nil
        self.runningSummary = ""
        self.finalSummary = nil
        let terms = glossary.split(whereSeparator: { $0.isNewline }).count
        Log.app.info("meeting context set — topicLen=\(topic.count, privacy: .public) glossaryTerms=\(terms, privacy: .public) docLen=\(document.count, privacy: .public)")

        let documentSnapshot = document
        guard !documentSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let existingTerms = DocumentTermExtractor.glossaryLines(from: glossary)
        let extractionID = UUID()
        let limit = DocumentTermExtractor.defaultLimit
        documentTermExtractionID = extractionID

        Task.detached(priority: .utility) {
            let terms = DocumentTermExtractor.extract(
                from: documentSnapshot,
                existingTerms: existingTerms,
                limit: limit
            )
            await MainActor.run {
                guard Self.shared.documentTermExtractionID == extractionID else { return }
                Self.shared.documentTerms = terms
                Log.app.info("document terms extracted count=\(terms.count, privacy: .public)")
            }
        }

        // 문서 요약본 1회 생성(요약 provider). 실패/미설정이면 nil 유지 → 요약은 excerpt 폴백.
        // 토큰 가드로 다음 회의가 시작되면 늦게 도착한 결과를 버린다(세션 누수 방지).
        // 위 documentTerms는 CPU-bound라 Task.detached + MainActor.run을 쓰지만, 여기는 async
        // 네트워크 I/O이므로 @MainActor를 상속하는 Task {}로 충분하다(suspension 중 MainActor 양보).
        // Task.detached로 "통일"하지 말 것 — 그 경우 documentSummary 쓰기에 MainActor.run 래핑이 필요해진다.
        let summaryID = UUID()
        documentSummaryGenerationID = summaryID
        Task {
            let summary = await SummaryService.shared.generateDocumentSummary(document: documentSnapshot)
            guard Self.shared.documentSummaryGenerationID == summaryID else { return }
            Self.shared.documentSummary = summary
        }
    }

    /// 맥락 초기화.
    public func clear() {
        topic = ""
        glossary = ""
        document = ""
        calendarEventIdentifier = nil
        documentTerms = []
        documentTermExtractionID = nil
        documentSummary = nil
        documentSummaryGenerationID = nil
        runningSummary = ""
        finalSummary = nil
    }
}
