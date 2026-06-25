import Foundation

public struct LLMProviderRegistry: Sendable {
    public static let shared = LLMProviderRegistry()

    public let descriptors: [LLMProviderDescriptor]

    public init(descriptors: [LLMProviderDescriptor] = Self.defaultDescriptors) {
        self.descriptors = descriptors
    }

    public func descriptor(for id: LLMProviderID) -> LLMProviderDescriptor? {
        descriptors.first { $0.id == id }
    }

    public func providerID(forLegacyCorrectionProviderRawValue rawValue: String) -> LLMProviderID? {
        switch rawValue {
        case "gemini":
            return .geminiAccount
        case "copilot":
            return .copilot
        case "codex":
            return .chatGPTAccount
        default:
            return nil
        }
    }

    public func legacyCorrectionProviderRawValue(for id: LLMProviderID) -> String? {
        switch id {
        case .geminiAccount:
            return "gemini"
        case .copilot:
            return "copilot"
        case .chatGPTAccount:
            return "codex"
        case .local, .gpt, .gemini, .claude, .claudeCodeCLI, .openRouter:
            return nil
        }
    }

    public func textGenerationProvider(for id: LLMProviderID) -> (any LLMTextGenerationProvider)? {
        if id == .local {
            return LocalLLMProvider(registry: self)
        }
        if id == .claudeCodeCLI {
            return ClaudeCodeCLIProvider(registry: self)
        }
        if let legacyProvider = LegacyAccountLLMTextProvider(providerID: id, registry: self) {
            return legacyProvider
        }
        return LLMAPIKeyTextProvider(providerID: id, registry: self)
    }

    public func embeddingProvider(for id: LLMProviderID) -> (any LLMEmbeddingProvider)? {
        switch id {
        case .local:
            return LocalHashEmbeddingProvider(registry: self)
        case .gpt, .gemini, .claude, .claudeCodeCLI, .openRouter, .copilot, .chatGPTAccount, .geminiAccount:
            return nil
        }
    }
}

extension LLMProviderRegistry {
    public static let defaultDescriptors: [LLMProviderDescriptor] = [
        LLMProviderDescriptor(
            id: .local,
            description: "외부 로컬 런타임으로 교정, 요약, 검색 답변과 기기 내 검색을 실행해요.",
            authKind: .local,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer, .embedding]
        ),
        LLMProviderDescriptor(
            id: .gpt,
            description: "OpenAI 공식 API 키로 교정, 요약, 질의응답을 실행해요.",
            authKind: .apiKey,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer, .embedding]
        ),
        LLMProviderDescriptor(
            id: .gemini,
            description: "Google Gemini 공식 API 키로 교정, 요약, 질의응답을 실행해요.",
            authKind: .apiKey,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer, .embedding]
        ),
        LLMProviderDescriptor(
            id: .claude,
            description: "Anthropic Claude API 키로 긴 회의 문맥을 정리해요.",
            authKind: .apiKey,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer]
        ),
        LLMProviderDescriptor(
            id: .claudeCodeCLI,
            description: "로컬 Claude Code CLI 로그인으로 교정, 회의록 정리, 검색 답변을 실행해요.",
            authKind: .cliPath,
            requiresWarning: true,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer]
        ),
        LLMProviderDescriptor(
            id: .openRouter,
            description: "OpenRouter API 키로 여러 모델 중 하나를 선택해요.",
            authKind: .apiKey,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer]
        ),
        LLMProviderDescriptor(
            id: .copilot,
            description: "GitHub Copilot 계정으로 교정, 요약, 검색 답변을 실행해요.",
            authKind: .accountLogin,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer]
        ),
        LLMProviderDescriptor(
            id: .chatGPTAccount,
            description: "GPT 계정 로그인으로 교정, 요약, 검색 답변을 실행해요.",
            authKind: .accountLogin,
            requiresWarning: true,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer]
        ),
        LLMProviderDescriptor(
            id: .geminiAccount,
            description: "Gemini 계정 로그인으로 교정, 요약, 검색 답변을 실행해요.",
            authKind: .accountLogin,
            requiresWarning: true,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer]
        )
    ]
}
