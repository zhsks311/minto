import Foundation
import SwiftUI

@MainActor
public final class MeetingSearchAnswerSettingsService: ObservableObject {
    public static let shared = MeetingSearchAnswerSettingsService()

    public static let enabledKey = "meetingSearchAnswerEnabled"
    public static let providerKey = "meetingSearchAnswerProvider"

    private let defaults: UserDefaults

    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @Published public var selectedProvider: LLMProviderSelection {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Self.providerKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        let rawProvider = defaults.string(forKey: Self.providerKey) ?? LLMProviderSelection.none.rawValue
        self.selectedProvider = LLMProviderSelection(rawValue: rawProvider) ?? .none
    }

    public func selectedTextProvider() -> (any LLMTextGenerationProvider)? {
        guard isEnabled, let providerID = selectedProvider.providerID else { return nil }
        guard let provider = LLMProviderRegistry.shared.textGenerationProvider(for: providerID),
              provider.descriptor.supportedCapabilities.contains(.answer)
        else { return nil }
        return provider
    }
}
