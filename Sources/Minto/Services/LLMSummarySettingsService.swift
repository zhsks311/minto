import Foundation
import SwiftUI

@MainActor
public final class LLMSummarySettingsService: ObservableObject {
    public static let shared = LLMSummarySettingsService()

    public static let enabledKey = "llmSummaryEnabled"
    public static let providerKey = "llmSummaryProvider"
    public static let migratedKey = "llmSummaryProviderMigrated"

    private let defaults: UserDefaults

    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @Published public var selectedProvider: LLMProviderSelection {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Self.providerKey) }
    }

    @Published public var hasMigratedFromCorrectionProvider: Bool {
        didSet { defaults.set(hasMigratedFromCorrectionProvider, forKey: Self.migratedKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        let rawProvider = defaults.string(forKey: Self.providerKey) ?? LLMProviderSelection.none.rawValue
        self.selectedProvider = LLMProviderSelection(rawValue: rawProvider) ?? .none
        self.hasMigratedFromCorrectionProvider = defaults.object(forKey: Self.migratedKey) as? Bool ?? false
    }

    public func migrateIfNeeded(from correctionProvider: LLMProviderSelection) {
        guard !hasMigratedFromCorrectionProvider else { return }
        hasMigratedFromCorrectionProvider = true
        guard correctionProvider != .none else { return }
        isEnabled = true
        selectedProvider = correctionProvider
    }

    public func selectedTextProvider() -> (any LLMTextGenerationProvider)? {
        guard isEnabled, let providerID = selectedProvider.providerID else { return nil }
        return LLMProviderRegistry.shared.textGenerationProvider(for: providerID)
    }
}
