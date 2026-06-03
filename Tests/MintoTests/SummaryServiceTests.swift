import Testing
@testable import MintoCore
import Foundation

/// SummaryService의 fail-soft·빈 회의·세션 누수 방지를 검증한다(네트워크 불필요, CI).
/// 라이브 mic 녹음·긴 회의 evict 전체 플로우는 앱 실행이 필요해 여기서 다루지 않는다(수동).
@MainActor
@Suite("SummaryService fail-soft / 빈 회의", .serialized)
struct SummaryServiceTests {

    @Test("provider none이면 증분 요약은 LLM 호출 없이 nil, runningSummary 미변경")
    func incrementalNilWhenProviderNone() async {
        let saved = LLMCorrectionService.shared.selectedProvider
        LLMCorrectionService.shared.selectedProvider = .none
        defer { LLMCorrectionService.shared.selectedProvider = saved }
        MeetingContext.shared.start(topic: "", glossary: "")
        defer { MeetingContext.shared.clear() }

        let result = await SummaryService.shared.generateIncremental(correctedBatch: "안건을 상정합니다.")
        #expect(result == nil)
        #expect(MeetingContext.shared.runningSummary.isEmpty)
    }

    @Test("빈 회의(누적·tail 모두 없음)면 최종 요약은 LLM 미호출로 nil")
    func finalNilWhenEmpty() async {
        let saved = LLMCorrectionService.shared.selectedProvider
        // provider가 있어도 요약할 내용이 없으면 LLM을 부르지 않고 nil(가드). 네트워크 미발생.
        LLMCorrectionService.shared.selectedProvider = .codex
        defer { LLMCorrectionService.shared.selectedProvider = saved }
        MeetingContext.shared.start(topic: "", glossary: "")
        defer { MeetingContext.shared.clear() }

        let result = await SummaryService.shared.generateFinal(tailText: "   ")
        #expect(result == nil)
    }

    @Test("빈 배치는 증분 요약을 건너뛴다(nil)")
    func incrementalSkipsEmptyBatch() async {
        MeetingContext.shared.start(topic: "", glossary: "")
        defer { MeetingContext.shared.clear() }
        let result = await SummaryService.shared.generateIncremental(correctedBatch: "   \n ")
        #expect(result == nil)
    }

    @Test("start/clear가 요약 상태를 리셋 — 세션 간 요약 누수 없음")
    func startClearResetsSummary() {
        MeetingContext.shared.runningSummary = "이전 회의 요약"
        MeetingContext.shared.finalSummary = "이전 최종 요약"
        MeetingContext.shared.start(topic: "새 회의", glossary: "")
        #expect(MeetingContext.shared.runningSummary.isEmpty)
        #expect(MeetingContext.shared.finalSummary.isEmpty)

        MeetingContext.shared.runningSummary = "진행 중"
        MeetingContext.shared.clear()
        #expect(MeetingContext.shared.runningSummary.isEmpty)
        #expect(MeetingContext.shared.finalSummary.isEmpty)
    }
}
