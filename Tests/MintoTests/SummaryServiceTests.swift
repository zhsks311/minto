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
        let summarySnapshot = SummarySettingsSnapshot.capture()
        LLMCorrectionService.shared.selectedProvider = .none
        LLMSummarySettingsService.shared.isEnabled = false
        LLMSummarySettingsService.shared.setOverride(.none)
        defer {
            LLMCorrectionService.shared.selectedProvider = saved
            summarySnapshot.restore()
        }
        MeetingContext.shared.start(topic: "", glossary: "")
        defer { MeetingContext.shared.clear() }

        let result = await SummaryService.shared.generateIncremental(correctedBatch: "안건을 상정합니다.")
        #expect(result == nil)
        #expect(MeetingContext.shared.runningSummary.isEmpty)
    }

    @Test("빈 회의(누적·tail 모두 없음)면 최종 요약은 LLM 미호출로 nil")
    func finalNilWhenEmpty() async {
        let saved = LLMCorrectionService.shared.selectedProvider
        let summarySnapshot = SummarySettingsSnapshot.capture()
        // provider가 있어도 요약할 내용이 없으면 LLM을 부르지 않고 nil(가드). 네트워크 미발생.
        LLMCorrectionService.shared.selectedProvider = .codex
        LLMSummarySettingsService.shared.isEnabled = true
        LLMSummarySettingsService.shared.setOverride(.codex)
        defer {
            LLMCorrectionService.shared.selectedProvider = saved
            summarySnapshot.restore()
        }
        MeetingContext.shared.start(topic: "", glossary: "")
        defer { MeetingContext.shared.clear() }

        let result = await SummaryService.shared.generateFinal(transcript: "   ")
        #expect(result == nil)
    }

    @Test("provider none이어도 누적 요약이 있으면 최종 요약은 평문 폴백한다")
    func finalFallsBackToRunningSummaryWhenProviderNone() async {
        let saved = LLMCorrectionService.shared.selectedProvider
        let summarySnapshot = SummarySettingsSnapshot.capture()
        LLMCorrectionService.shared.selectedProvider = .none
        LLMSummarySettingsService.shared.isEnabled = false
        LLMSummarySettingsService.shared.setOverride(.none)
        defer {
            LLMCorrectionService.shared.selectedProvider = saved
            summarySnapshot.restore()
        }
        MeetingContext.shared.start(topic: "", glossary: "")
        MeetingContext.shared.runningSummary = "누적 요약입니다."
        defer { MeetingContext.shared.clear() }

        let result = await SummaryService.shared.generateFinal(transcript: "[00:01] 실제 전사")

        #expect(result?.leadAnswer == "누적 요약입니다.")
        #expect(MeetingContext.shared.finalSummary?.leadAnswer == "누적 요약입니다.")
    }

    @Test("빈 배치는 증분 요약을 건너뛴다(nil)")
    func incrementalSkipsEmptyBatch() async {
        MeetingContext.shared.start(topic: "", glossary: "")
        defer { MeetingContext.shared.clear() }
        let result = await SummaryService.shared.generateIncremental(correctedBatch: "   \n ")
        #expect(result == nil)
    }

    @Test("요약 설정 migration은 교정 provider를 한 번만 복사한다")
    func summarySettingsMigrationRunsOnce() {
        let defaults = InMemoryUserDefaults()
        // activeProvider를 .none으로 고정해 외부 LLMCorrectionService 상태에 의존하지 않는다.
        let settings = LLMSummarySettingsService(defaults: defaults, activeProvider: { .none })
        settings.migrateIfNeeded(from: .gptAPI)

        #expect(settings.hasMigratedFromCorrectionProvider)
        #expect(settings.isEnabled)
        #expect(settings.effectiveProvider == .gptAPI)

        settings.isEnabled = false
        // .none setter는 override를 제거(follow 전환)한다.
        settings.setOverride(.none)
        #expect(!settings.hasOverride)
        settings.migrateIfNeeded(from: .claudeAPI)

        // 두 번째 migrate는 hasMigrated 플래그로 차단되어 아무 변화 없다.
        #expect(settings.isEnabled == false)
        #expect(!settings.hasOverride)
    }

    @Test("교정을 꺼도 요약 provider는 독립적으로 유지된다")
    func summaryProviderIsIndependentFromCorrectionProvider() {
        let saved = LLMCorrectionService.shared.selectedProvider
        let summarySnapshot = SummarySettingsSnapshot.capture()
        defer {
            LLMCorrectionService.shared.selectedProvider = saved
            summarySnapshot.restore()
        }

        LLMCorrectionService.shared.selectedProvider = .none
        LLMSummarySettingsService.shared.isEnabled = true
        LLMSummarySettingsService.shared.setOverride(.codex)

        #expect(LLMCorrectionService.shared.selectedTextProvider() == nil)
        #expect(LLMSummarySettingsService.shared.selectedTextProvider()?.descriptor.id == .chatGPTAccount)
    }

    @Test("parseStructured: 계층형 JSON 전체 필드 파싱")
    func parsesValidJSON() {
        let raw = #"""
        {"title":"제목","leadQuestion":"핵심 질문?","leadAnswer":"핵심 답변","keywords":["kw1","kw2"],
         "decisions":[{"text":"DB 형상 관리는 flyway를 우선 검토","time":"00:40"}],
         "actionItems":[{"task":"마이그레이션 테스트 케이스 정리","owner":"민수","due":"다음 회의","time":"01:20"}],
         "openQuestions":[{"text":"운영 DB 적용 절차는 추가 확인 필요","time":"02:10"}],
         "sections":[{"title":"1. 주제","time":"00:30","points":[{"text":"카테고리","subPoints":["세부1","세부2"]}]}]}
        """#
        let s = SummaryService.parseStructured(raw)
        #expect(s?.title == "제목")
        #expect(s?.leadQuestion == "핵심 질문?")
        #expect(s?.leadAnswer == "핵심 답변")
        #expect(s?.keywords == ["kw1", "kw2"])
        #expect(s?.decisions.first?.text == "DB 형상 관리는 flyway를 우선 검토")
        #expect(s?.decisions.first?.time == "00:40")
        #expect(s?.actionItems.first?.task == "마이그레이션 테스트 케이스 정리")
        #expect(s?.actionItems.first?.owner == "민수")
        #expect(s?.actionItems.first?.due == "다음 회의")
        #expect(s?.openQuestions.first?.text == "운영 DB 적용 절차는 추가 확인 필요")
        #expect(s?.sections.count == 1)
        #expect(s?.sections.first?.title == "1. 주제")
        #expect(s?.sections.first?.time == "00:30")
        #expect(s?.sections.first?.points.first?.text == "카테고리")
        #expect(s?.sections.first?.points.first?.subPoints == ["세부1", "세부2"])
    }

    @Test("parseStructured: 코드펜스·앞뒤 설명이 섞여도 JSON만 추출")
    func parsesWithFencesAndProse() {
        let raw = "여기 요약입니다:\n```json\n{\"leadAnswer\":\"답변만\"}\n```\n끝."
        #expect(SummaryService.parseStructured(raw)?.leadAnswer == "답변만")
    }

    @Test("parseStructured: 일부 필드 누락도 기본값으로 lenient 디코딩")
    func parsesPartial() {
        let s = SummaryService.parseStructured(#"{"leadAnswer":"답변만 있음"}"#)
        #expect(s?.leadAnswer == "답변만 있음")
        #expect(s?.title == "")
        #expect(s?.sections.isEmpty == true)
    }

    @Test("parseStructured: JSON 아님 / 내용 없음 → nil(평문 폴백 유도)")
    func parseFailsToNil() {
        #expect(SummaryService.parseStructured("그냥 평문 텍스트") == nil)              // 중괄호 없음
        #expect(SummaryService.parseStructured(#"{"title":"","leadAnswer":""}"#) == nil) // 의미 내용 없음
    }

    @Test("MeetingSummary.markdown: 계층 렌더")
    func markdownRender() {
        let s = MeetingSummary(
            title: "T",
            leadQuestion: "핵심 질문?",
            leadAnswer: "핵심 답변",
            sections: [.init(title: "1. 주제", time: "01:20",
                             points: [.init(text: "카테고리", subPoints: ["세부1"])])],
            keywords: ["k1"],
            decisions: [.init(text: "방식 A로 진행", time: "00:30")],
            actionItems: [.init(task: "테스트 작성", owner: "민수", due: "금요일", time: "00:45")],
            openQuestions: [.init(text: "배포 순서 확인", time: "01:10")]
        )
        let md = s.markdown()
        #expect(md.contains("> 핵심 질문?"))
        #expect(md.contains("**핵심 답변**"))
        #expect(md.contains("## 결정사항"))
        #expect(md.contains("- `00:30` 방식 A로 진행"))
        #expect(md.contains("## 할 일"))
        #expect(md.contains("- [ ] `00:45` 테스트 작성 _(담당: 민수 · 기한: 금요일)_"))
        #expect(md.contains("## 미해결 질문"))
        #expect(md.contains("- `01:10` 배포 순서 확인"))
        #expect(md.contains("### 1. 주제"))
        #expect(md.contains("`01:20`"))
        #expect(md.contains("- 카테고리"))
        #expect(md.contains("  - 세부1"))
        #expect(md.contains("키워드: k1"))
    }

    @Test("start/clear가 요약 상태를 리셋 — 세션 간 요약 누수 없음")
    func startClearResetsSummary() {
        MeetingContext.shared.runningSummary = "이전 회의 요약"
        MeetingContext.shared.finalSummary = .plain("이전 최종 요약")
        MeetingContext.shared.start(topic: "새 회의", glossary: "")
        #expect(MeetingContext.shared.runningSummary.isEmpty)
        #expect(MeetingContext.shared.finalSummary == nil)

        MeetingContext.shared.runningSummary = "진행 중"
        MeetingContext.shared.clear()
        #expect(MeetingContext.shared.runningSummary.isEmpty)
        #expect(MeetingContext.shared.finalSummary == nil)
    }
}

@MainActor
private struct SummarySettingsSnapshot {
    let isEnabled: Bool
    /// override만 보존한다 — effective를 복원하면 follow 상태가 override로 오염된다.
    let overrideProvider: LLMProviderSelection?
    let hasMigrated: Bool

    static func capture() -> SummarySettingsSnapshot {
        let settings = LLMSummarySettingsService.shared
        return SummarySettingsSnapshot(
            isEnabled: settings.isEnabled,
            overrideProvider: settings.hasOverride ? settings.effectiveProvider : nil,
            hasMigrated: settings.hasMigratedFromCorrectionProvider
        )
    }

    func restore() {
        let settings = LLMSummarySettingsService.shared
        settings.isEnabled = isEnabled
        if let provider = overrideProvider {
            settings.setOverride(provider)
        } else {
            settings.clearOverride()
        }
        settings.hasMigratedFromCorrectionProvider = hasMigrated
    }
}
