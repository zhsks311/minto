import Foundation

public enum LLMProviderSelection: String, CaseIterable {
    case none = "none"
    case local = "local"
    case gptAPI = "gpt_api"
    case geminiAPI = "gemini_api"
    case claudeAPI = "claude_api"
    case claudeCodeCLI = "claude_code_cli"
    case openRouterAPI = "openrouter_api"
    case gemini = "gemini"
    case copilot = "copilot"
    case codex = "codex"

    public var providerID: LLMProviderID? {
        switch self {
        case .none:
            return nil
        case .local:
            return .local
        case .gptAPI:
            return .gpt
        case .geminiAPI:
            return .gemini
        case .claudeAPI:
            return .claude
        case .claudeCodeCLI:
            return .claudeCodeCLI
        case .openRouterAPI:
            return .openRouter
        case .gemini, .copilot, .codex:
            return LLMProviderRegistry.shared.providerID(forLegacyCorrectionProviderRawValue: rawValue)
        }
    }

    public var label: String {
        if self == .none { return "사용 안 함" }
        guard let providerID else { return rawValue }
        let descriptor = LLMProviderRegistry.shared.descriptor(for: providerID)
        return descriptor?.displayName ?? providerID.displayName
    }

    public init?(providerID: LLMProviderID) {
        switch providerID {
        case .local:
            self = .local
        case .gpt:
            self = .gptAPI
        case .gemini:
            self = .geminiAPI
        case .claude:
            self = .claudeAPI
        case .claudeCodeCLI:
            self = .claudeCodeCLI
        case .openRouter:
            self = .openRouterAPI
        case .copilot, .chatGPTAccount, .geminiAccount:
            guard let rawValue = LLMProviderRegistry.shared.legacyCorrectionProviderRawValue(for: providerID),
                  let provider = Self(rawValue: rawValue)
            else {
                return nil
            }
            self = provider
        }
    }

    public var requiresWarning: Bool {
        guard let providerID else { return false }
        return LLMProviderRegistry.shared.descriptor(for: providerID)?.requiresWarning ?? false
    }
}
