import os
import Foundation

// MARK: - 재요약 결과

public enum SummaryRetryFailureReason: Sendable {
    case emptyTranscript
    case llmFailed
    case stillPlainFallback
    case saveFailed
}

public enum SummaryRetryResult: Sendable {
    case success(MeetingRecord)
    case failure(SummaryRetryFailureReason)
}

// MARK: - 의존성 프로토콜 (테스트 교체용)

@MainActor
protocol MeetingSummaryRetryGenerating: AnyObject {
    // generateFinal(transcript:context:) 오버로드를 사용한다 — live MeetingContext.shared를
    // 오염시키지 않기 위해 단독 context를 명시 주입하는 경로가 필요하다.
    func generateFinal(transcript: String, context: SummaryGenerationContext) async -> MeetingSummary?
}

extension SummaryService: MeetingSummaryRetryGenerating {}

@MainActor
protocol MeetingSummaryRetryStoring: AnyObject {
    @discardableResult
    func save(_ record: MeetingRecord) -> MeetingSaveResult
}

extension MeetingStore: MeetingSummaryRetryStoring {}

@MainActor
protocol MeetingSummaryRetryCandidateIngesting: AnyObject {
    func ingestCandidates(from record: MeetingRecord)
}

extension GlossaryStore: MeetingSummaryRetryCandidateIngesting {}

// MARK: - Use Case

/// 평문 폴백 요약(isPlainFallback)을 구조화 요약으로 재시도한다.
///
/// 재시도 흐름:
/// 1. record.transcript → "[MM:SS] text" 포맷 전사 재구성
/// 2. SummaryService.generateFinal(transcript:context:) 호출 (glossary 주입)
/// 3. 결과가 nil / isEmpty / isPlainFallback 이면 기존 요약 보존 후 failure 반환
/// 4. 구조화 성공 시 record.summary만 교체해 store.save() — 저장 실패 시 메모리 무변경으로 failure
/// 5. 저장 성공 후 GlossaryStore.ingestCandidates(from:) 호출 (id-diff 구독 우회)
@MainActor
public final class MeetingSummaryRetryUseCase {

    private let summaryService: any MeetingSummaryRetryGenerating
    private let store: any MeetingSummaryRetryStoring
    private let glossaryStore: any MeetingSummaryRetryCandidateIngesting
    /// topic 기반 용어집 텍스트를 제공한다. 기본값은 GlossaryStore.shared 기반 선별.
    /// 테스트에서 주입해 GlossaryStore 의존을 끊는다.
    private let glossaryResolver: @MainActor (String) -> String

    init(
        summaryService: any MeetingSummaryRetryGenerating = SummaryService.shared,
        store: any MeetingSummaryRetryStoring = MeetingStore.shared,
        glossaryStore: any MeetingSummaryRetryCandidateIngesting = GlossaryStore.shared,
        glossaryResolver: (@MainActor (String) -> String)? = nil
    ) {
        self.summaryService = summaryService
        self.store = store
        self.glossaryStore = glossaryStore
        // 기본값: 현재 용어집에서 topic 기반 상위 8개 선별 → 1,200자 예산 적용.
        // 라이브 요약과 동일한 GlossaryContextResolver 경로를 사용한다.
        self.glossaryResolver = glossaryResolver ?? { topic in
            let entries = GlossaryStore.shared.candidates(for: topic)
            return GlossaryContextResolver().resolve(manualGlossary: "", selectedEntries: entries)
        }
    }

    /// record의 전사를 기반으로 구조화 요약을 재시도한다.
    /// - Parameter record: 재요약 시점의 복사본. 클로저 캡처 시에도 시점이 고정된다.
    /// - Returns: 성공 시 `.success(updated record)`, 실패 시 `.failure(reason)`.
    ///            기존 record는 실패 시 절대 수정하지 않는다.
    public func retry(record: MeetingRecord) async -> SummaryRetryResult {
        let segmentCount = record.transcript.count
        Log.summary.info("summary retry start segmentCount=\(segmentCount, privacy: .public)")

        let transcript = Self.buildTranscript(from: record.transcript)
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.summary.error("summary retry failed reason=\(String(describing: SummaryRetryFailureReason.emptyTranscript), privacy: .public)")
            return .failure(.emptyTranscript)
        }

        let glossary = glossaryResolver(record.topic)
        let context = SummaryGenerationContext(
            topic: record.topic,
            glossary: glossary,
            runningSummary: "",
            document: ""
        )

        guard let newSummary = await summaryService.generateFinal(transcript: transcript, context: context) else {
            Log.summary.error("summary retry failed reason=\(String(describing: SummaryRetryFailureReason.llmFailed), privacy: .public)")
            return .failure(.llmFailed)
        }

        // 빈 JSON `{}` → MeetingSummary() (isEmpty=true, isPlainFallback=false) 도 거부한다.
        guard !newSummary.isEmpty, !newSummary.isPlainFallback else {
            Log.summary.error("summary retry failed reason=\(String(describing: SummaryRetryFailureReason.stillPlainFallback), privacy: .public)")
            return .failure(.stillPlainFallback)
        }

        var updated = record
        updated.summary = newSummary

        // MeetingStore.save()는 디스크 write 성공 후에 메모리(meetings)를 갱신한다.
        // 따라서 .failed/.skippedEmpty 시 메모리는 원상태 — 별도 원복 불필요.
        guard store.save(updated) == .success else {
            Log.summary.error("summary retry failed reason=\(String(describing: SummaryRetryFailureReason.saveFailed), privacy: .public)")
            return .failure(.saveFailed)
        }

        glossaryStore.ingestCandidates(from: updated)

        let sectionCount = newSummary.sections.count
        let keywordCount = newSummary.keywords.count
        Log.summary.info("summary retry success sectionCount=\(sectionCount, privacy: .public) keywordCount=\(keywordCount, privacy: .public)")

        return .success(updated)
    }

    /// transcript segments → "[MM:SS] text" 포맷 문자열.
    /// 첫 세그먼트 기준 상대 시각. TranscriptionViewModel.finalizeMeeting 및
    /// MeetingFileImportUseCase.transcriptText 와 동일 포맷.
    static func buildTranscript(from segments: [Segment]) -> String {
        guard let first = segments.first else { return "" }
        return segments.map { seg in
            let s = max(0, Int(seg.timestamp.timeIntervalSince(first.timestamp).rounded()))
            return String(format: "[%02d:%02d] %@", s / 60, s % 60, seg.text)
        }.joined(separator: "\n")
    }
}
