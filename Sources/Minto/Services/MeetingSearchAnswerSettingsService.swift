import Foundation
import SwiftUI
import Combine

@MainActor
public final class MeetingSearchAnswerSettingsService: ObservableObject {
    public static let shared = MeetingSearchAnswerSettingsService(
        activeProviderPublisher: LLMCorrectionService.shared.$selectedProvider.eraseToAnyPublisher()
    )

    public static let enabledKey = "meetingSearchAnswerEnabled"
    public static let providerKey = "meetingSearchAnswerProvider"
    /// follow → override 마이그레이션 완료 플래그.
    public static let followMigratedKey = "meetingSearchAnswerFollowMigrated"

    private let defaults: UserDefaults
    /// 활성 provider를 반환하는 클로저. 순환 참조 없이 LLMCorrectionService.shared를 참조한다.
    private let activeProvider: @MainActor () -> LLMProviderSelection
    private var activeProviderCancellable: AnyCancellable?

    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// override 값. nil = follow(활성 provider를 따름).
    /// 외부에서는 effectiveProvider를 사용한다.
    private var providerOverride: LLMProviderSelection? {
        didSet {
            if let override = providerOverride {
                defaults.set(override.rawValue, forKey: Self.providerKey)
            } else {
                defaults.removeObject(forKey: Self.providerKey)
            }
            objectWillChange.send()
        }
    }

    /// 실제 사용할 provider. override가 있으면 그것을, 없으면 활성 provider를 따른다.
    @Published public private(set) var effectiveProvider: LLMProviderSelection


    public init(
        defaults: UserDefaults = .standard,
        activeProvider: (@MainActor () -> LLMProviderSelection)? = nil,
        activeProviderPublisher: AnyPublisher<LLMProviderSelection, Never>? = nil
    ) {
        self.defaults = defaults
        self.activeProvider = activeProvider ?? { LLMCorrectionService.shared.selectedProvider }
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false

        // 저장된 override 로드
        let rawProvider = defaults.string(forKey: Self.providerKey)
        if let raw = rawProvider, let selection = LLMProviderSelection(rawValue: raw) {
            self.providerOverride = selection
            self.effectiveProvider = selection
        } else {
            self.providerOverride = nil
            self.effectiveProvider = .none
        }
        refreshEffective()
        if let activeProviderPublisher {
            startObservingActiveProvider(publisher: activeProviderPublisher)
        }
    }

    /// effectiveProvider를 현재 override/active 상태에 맞게 갱신한다.
    /// 활성 provider가 변경될 때 호출한다.
    public func refreshEffective() {
        let newEffective = providerOverride ?? activeProvider()
        if effectiveProvider != newEffective {
            effectiveProvider = newEffective
        }
    }

    private func startObservingActiveProvider(publisher: AnyPublisher<LLMProviderSelection, Never>) {
        guard activeProviderCancellable == nil else { return }
        activeProviderCancellable = publisher
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshEffective()
                }
            }
    }

    /// override를 명시적으로 설정한다. .none을 전달하면 follow로 전환한다.
    public func setOverride(_ provider: LLMProviderSelection) {
        if provider == .none {
            providerOverride = nil
        } else {
            providerOverride = provider
        }
        refreshEffective()
    }

    /// override를 제거하고 follow 모드로 전환한다.
    public func clearOverride() {
        providerOverride = nil
        refreshEffective()
    }

    public var hasOverride: Bool {
        providerOverride != nil
    }

    // MARK: - follow 시맨틱 마이그레이션 (기존 저장값 처리)

    /// 기존 저장값을 follow 시맨틱으로 마이그레이션한다.
    /// - 저장값 == 활성 provider → 키 제거(follow로 전환)
    /// - 저장값 != 활성 provider → override 유지(현재 의도 보존)
    /// - 저장값 없음 → 이미 follow
    public func migrateToFollowSemanticIfNeeded() {
        let alreadyMigrated = defaults.object(forKey: Self.followMigratedKey) as? Bool ?? false
        guard !alreadyMigrated else { return }
        defaults.set(true, forKey: Self.followMigratedKey)

        guard let current = providerOverride else {
            // 저장값 없음 → 이미 follow
            refreshEffective()
            return
        }
        let active = activeProvider()
        if active != .none, current == active {
            // 저장값이 활성 provider와 같으면 follow로 전환
            providerOverride = nil
        }
        // active가 .none이거나 저장값이 다르면 override 유지
        refreshEffective()
    }

    // MARK: - Provider 해석

    public func selectedTextProvider() -> (any LLMTextGenerationProvider)? {
        guard isEnabled, let providerID = effectiveProvider.providerID else { return nil }
        guard let provider = LLMProviderRegistry.shared.textGenerationProvider(for: providerID),
              provider.descriptor.supportedCapabilities.contains(.answer)
        else { return nil }
        return provider
    }
}
