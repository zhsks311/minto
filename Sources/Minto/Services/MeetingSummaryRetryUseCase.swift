import os
import Foundation

// MARK: - 재요약 결과

public enum SummaryRetryFailureReason: Sendable {
    case emptyTranscript
    case llmFailed
    case stillPlainFallback
}

public enum SummaryRetryResult: Sendable {
    case success(MeetingRecord)
    case failure(SummaryRetryFailureReason)
}

// MARK: - 의존성 프로토콜 (테스트 교체용)

@MainActor
protocol MeetingSummaryRetryGenerating: AnyObject {
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
/// 2. SummaryService.generateFinal(transcript:context:) 호출
/// 3. 결과가 nil이거나 isPlainFallback이면 기존 요약 보존 후 failure 반환
/// 4. 구조화 성공 시 record.summary만 교체해 store.save()
/// 5. GlossaryStore.ingestCandidates(from:) 호출 (id-diff 구독 우회)
@MainActor
public final class MeetingSummaryRetryUseCase {

    private let summaryService: any MeetingSummaryRetryGenerating
    private let store: any MeetingSummaryRetryStoring
    private let glossaryStore: any MeetingSummaryRetryCandidateIngesting

    init(
        summaryService: any MeetingSummaryRetryGenerating = SummaryService.shared,
        store: any MeetingSummaryRetryStoring = MeetingStore.shared,
        glossaryStore: any MeetingSummaryRetryCandidateIngesting = GlossaryStore.shared
    ) {
        self.summaryService = summaryService
        self.store = store
        self.glossaryStore = glossaryStore
    }

    /// record의 전사를 기반으로 구조화 요약을 재시도한다.
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

        let context = SummaryGenerationContext(
            topic: record.topic,
            glossary: "",
            runningSummary: "",
            document: ""
        )

        guard let newSummary = await summaryService.generateFinal(transcript: transcript, context: context) else {
            Log.summary.error("summary retry failed reason=\(String(describing: SummaryRetryFailureReason.llmFailed), privacy: .public)")
            return .failure(.llmFailed)
        }

        guard !newSummary.isPlainFallback else {
            Log.summary.error("summary retry failed reason=\(String(describing: SummaryRetryFailureReason.stillPlainFallback), privacy: .public)")
            return .failure(.stillPlainFallback)
        }

        var updated = record
        updated.summary = newSummary
        store.save(updated)
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
