import Foundation
import Testing
import Combine
@testable import MintoCore

@Suite("Provider follow 시맨틱 + 마이그레이션", .serialized)
struct ProviderFollowSemanticTests {

    // MARK: - LLMSummarySettingsService follow/override

    @MainActor
    @Test("요약 서비스: override 없으면 활성 provider를 따른다")
    func summaryFollowsActiveWhenNoOverride() {
        let defaults = InMemoryUserDefaults()
        let settings = LLMSummarySettingsService(defaults: defaults, activeProvider: { .gptAPI })

        // 저장값 없음 → follow
        #expect(!settings.hasOverride)
        settings.refreshEffective()
        #expect(settings.effectiveProvider == .gptAPI)
    }

    @MainActor
    @Test("요약 서비스: 활성 provider publisher 변경만으로 effectiveProvider를 갱신한다")
    func summaryFollowsActivePublisherWithoutManualRefresh() async {
        let defaults = InMemoryUserDefaults()
        let activeProvider = CurrentValueSubject<LLMProviderSelection, Never>(.gptAPI)
        let settings = LLMSummarySettingsService(
            defaults: defaults,
            activeProvider: { activeProvider.value },
            activeProviderPublisher: activeProvider.eraseToAnyPublisher()
        )

        #expect(settings.effectiveProvider == .gptAPI)

        activeProvider.send(.codex)

        #expect(await waitUntil { settings.effectiveProvider == .codex })
    }

    @MainActor
    @Test("요약 서비스: override 설정 시 활성 provider와 무관하게 유지된다")
    func summaryOverrideIgnoresActive() {
        let defaults = InMemoryUserDefaults()
        let settings = LLMSummarySettingsService(defaults: defaults, activeProvider: { .codex })

        settings.setOverride(.claudeAPI)
        #expect(settings.hasOverride)
        #expect(settings.effectiveProvider == .claudeAPI)

        // 활성이 바뀌어도 override 유지
        // (activeProvider 클로저를 바꿀 수 없으므로 refreshEffective로 검증)
        settings.refreshEffective()
        #expect(settings.effectiveProvider == .claudeAPI)
    }

    @MainActor
    @Test("요약 서비스: override가 있으면 활성 provider publisher 변경에 영향받지 않는다")
    func summaryOverrideIgnoresActivePublisher() async {
        let defaults = InMemoryUserDefaults()
        let activeProvider = CurrentValueSubject<LLMProviderSelection, Never>(.codex)
        let settings = LLMSummarySettingsService(
            defaults: defaults,
            activeProvider: { activeProvider.value },
            activeProviderPublisher: activeProvider.eraseToAnyPublisher()
        )

        settings.setOverride(.claudeAPI)
        activeProvider.send(.gptAPI)

        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(settings.effectiveProvider == .claudeAPI)
    }

    @MainActor
    @Test("요약 서비스: override 제거 후 활성 provider를 따른다")
    func summaryClearOverrideFallsBackToActive() {
        let defaults = InMemoryUserDefaults()
        let activeProvider = CurrentValueSubject<LLMProviderSelection, Never>(.gptAPI)
        let settings = LLMSummarySettingsService(defaults: defaults, activeProvider: { activeProvider.value })

        settings.setOverride(.claudeAPI)
        #expect(settings.effectiveProvider == .claudeAPI)

        settings.clearOverride()
        #expect(!settings.hasOverride)
        settings.refreshEffective()
        #expect(settings.effectiveProvider == .gptAPI)

        // 활성 변경 → effective도 변경
        activeProvider.send(.codex)
        settings.refreshEffective()
        #expect(settings.effectiveProvider == .codex)
    }

    // MARK: - MeetingSearchAnswerSettingsService follow/override

    @MainActor
    @Test("답변 서비스: override 없으면 활성 provider를 따른다")
    func answerFollowsActiveWhenNoOverride() {
        let defaults = InMemoryUserDefaults()
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults, activeProvider: { .codex })

        #expect(!settings.hasOverride)
        settings.refreshEffective()
        #expect(settings.effectiveProvider == .codex)
    }

    @MainActor
    @Test("답변 서비스: 활성 provider publisher 변경만으로 effectiveProvider를 갱신한다")
    func answerFollowsActivePublisherWithoutManualRefresh() async {
        let defaults = InMemoryUserDefaults()
        let activeProvider = CurrentValueSubject<LLMProviderSelection, Never>(.codex)
        let settings = MeetingSearchAnswerSettingsService(
            defaults: defaults,
            activeProvider: { activeProvider.value },
            activeProviderPublisher: activeProvider.eraseToAnyPublisher()
        )

        #expect(settings.effectiveProvider == .codex)

        activeProvider.send(.geminiAPI)

        #expect(await waitUntil { settings.effectiveProvider == .geminiAPI })
    }

    @MainActor
    @Test("답변 서비스: override 설정 시 활성 provider와 무관하게 유지된다")
    func answerOverrideIgnoresActive() {
        let defaults = InMemoryUserDefaults()
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults, activeProvider: { .codex })

        settings.setOverride(.gptAPI)
        #expect(settings.hasOverride)
        #expect(settings.effectiveProvider == .gptAPI)

        settings.refreshEffective()
        #expect(settings.effectiveProvider == .gptAPI)
    }

    @MainActor
    @Test("답변 서비스: override가 있으면 활성 provider publisher 변경에 영향받지 않는다")
    func answerOverrideIgnoresActivePublisher() async {
        let defaults = InMemoryUserDefaults()
        let activeProvider = CurrentValueSubject<LLMProviderSelection, Never>(.codex)
        let settings = MeetingSearchAnswerSettingsService(
            defaults: defaults,
            activeProvider: { activeProvider.value },
            activeProviderPublisher: activeProvider.eraseToAnyPublisher()
        )

        settings.setOverride(.gptAPI)
        activeProvider.send(.geminiAPI)

        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(settings.effectiveProvider == .gptAPI)
    }

    @MainActor
    @Test("답변 서비스: override 제거 후 활성 provider를 따른다")
    func answerClearOverrideFallsBackToActive() {
        let defaults = InMemoryUserDefaults()
        let activeProvider = CurrentValueSubject<LLMProviderSelection, Never>(.gptAPI)
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults, activeProvider: { activeProvider.value })

        settings.setOverride(.claudeAPI)
        settings.clearOverride()
        settings.refreshEffective()
        #expect(settings.effectiveProvider == .gptAPI)

        activeProvider.send(.geminiAPI)
        settings.refreshEffective()
        #expect(settings.effectiveProvider == .geminiAPI)
    }

    // MARK: - 마이그레이션: LLMSummarySettingsService

    @MainActor
    @Test("요약 마이그레이션: 저장값이 활성과 같으면 follow로 전환한다")
    func summaryMigrationSameValueBecomesFollow() {
        let defaults = InMemoryUserDefaults()
        defaults.set(LLMProviderSelection.codex.rawValue, forKey: LLMSummarySettingsService.providerKey)
        let settings = LLMSummarySettingsService(defaults: defaults, activeProvider: { .codex })

        settings.migrateToFollowSemanticIfNeeded()

        #expect(!settings.hasOverride)
        #expect(defaults.object(forKey: LLMSummarySettingsService.providerKey) == nil)
        // effectiveProvider는 활성 provider를 따른다
        settings.refreshEffective()
        #expect(settings.effectiveProvider == .codex)
    }

    @MainActor
    @Test("요약 마이그레이션: 저장값이 활성과 다르면 override 유지한다")
    func summaryMigrationDifferentValueKeepsOverride() {
        let defaults = InMemoryUserDefaults()
        defaults.set(LLMProviderSelection.claudeAPI.rawValue, forKey: LLMSummarySettingsService.providerKey)
        let settings = LLMSummarySettingsService(defaults: defaults, activeProvider: { .codex })

        settings.migrateToFollowSemanticIfNeeded()

        #expect(settings.hasOverride)
        #expect(settings.effectiveProvider == .claudeAPI)
    }

    @MainActor
    @Test("요약 마이그레이션: 저장값 없으면 follow 유지")
    func summaryMigrationNoValueStaysFollow() {
        let defaults = InMemoryUserDefaults()
        let settings = LLMSummarySettingsService(defaults: defaults, activeProvider: { .gptAPI })

        settings.migrateToFollowSemanticIfNeeded()

        #expect(!settings.hasOverride)
        settings.refreshEffective()
        #expect(settings.effectiveProvider == .gptAPI)
    }

    @MainActor
    @Test("요약 마이그레이션: 두 번 호출해도 두 번째는 무시된다")
    func summaryMigrationRunsOnce() {
        let defaults = InMemoryUserDefaults()
        defaults.set(LLMProviderSelection.codex.rawValue, forKey: LLMSummarySettingsService.providerKey)
        let settings = LLMSummarySettingsService(defaults: defaults, activeProvider: { .codex })

        settings.migrateToFollowSemanticIfNeeded()
        #expect(!settings.hasOverride)

        // override를 다시 설정한 뒤 두 번째 migrate는 아무것도 바꾸지 않는다
        settings.setOverride(.gptAPI)
        settings.migrateToFollowSemanticIfNeeded()
        #expect(settings.hasOverride)
        #expect(settings.effectiveProvider == .gptAPI)
    }

    // MARK: - 마이그레이션: MeetingSearchAnswerSettingsService

    @MainActor
    @Test("답변 마이그레이션: 저장값이 활성과 같으면 follow로 전환한다")
    func answerMigrationSameValueBecomesFollow() {
        let defaults = InMemoryUserDefaults()
        defaults.set(LLMProviderSelection.gptAPI.rawValue, forKey: MeetingSearchAnswerSettingsService.providerKey)
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults, activeProvider: { .gptAPI })

        settings.migrateToFollowSemanticIfNeeded()

        #expect(!settings.hasOverride)
        #expect(defaults.object(forKey: MeetingSearchAnswerSettingsService.providerKey) == nil)
    }

    @MainActor
    @Test("답변 마이그레이션: 저장값이 활성과 다르면 override 유지한다")
    func answerMigrationDifferentValueKeepsOverride() {
        let defaults = InMemoryUserDefaults()
        defaults.set(LLMProviderSelection.openRouterAPI.rawValue, forKey: MeetingSearchAnswerSettingsService.providerKey)
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults, activeProvider: { .codex })

        settings.migrateToFollowSemanticIfNeeded()

        #expect(settings.hasOverride)
        #expect(settings.effectiveProvider == .openRouterAPI)
    }

    @MainActor
    @Test("답변 마이그레이션: 활성이 .none이면 저장값이 같아도 override 유지한다")
    func answerMigrationActiveNoneKeepsOverride() {
        let defaults = InMemoryUserDefaults()
        defaults.set(LLMProviderSelection.gptAPI.rawValue, forKey: MeetingSearchAnswerSettingsService.providerKey)
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults, activeProvider: { .none })

        settings.migrateToFollowSemanticIfNeeded()

        // active가 .none이면 "같으면 follow" 조건이 성립하지 않으므로 override 유지
        #expect(settings.hasOverride)
        #expect(settings.effectiveProvider == .gptAPI)
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 500_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let step: UInt64 = 10_000_000
        let attempts = max(1, Int(timeoutNanoseconds / step))
        for _ in 0..<attempts {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: step)
        }
        return condition()
    }
}
