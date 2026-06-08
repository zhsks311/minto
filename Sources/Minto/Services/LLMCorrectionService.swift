import Foundation
import SwiftUI

@MainActor
public final class LLMCorrectionService: ObservableObject {

    public enum Provider: String, CaseIterable {
        case none    = "none"
        case gptAPI = "gpt_api"
        case geminiAPI = "gemini_api"
        case claudeAPI = "claude_api"
        case openRouterAPI = "openrouter_api"
        case gemini  = "gemini"
        case copilot = "copilot"
        case codex   = "codex"

        public var providerID: LLMProviderID? {
            switch self {
            case .none:
                return nil
            case .gptAPI:
                return .gpt
            case .geminiAPI:
                return .gemini
            case .claudeAPI:
                return .claude
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
            case .gpt:
                self = .gptAPI
            case .gemini:
                self = .geminiAPI
            case .claude:
                self = .claudeAPI
            case .openRouter:
                self = .openRouterAPI
            case .copilot, .chatGPTAccount, .geminiAccount:
                guard let rawValue = LLMProviderRegistry.shared.legacyCorrectionProviderRawValue(for: providerID),
                      let provider = Self(rawValue: rawValue)
                else {
                    return nil
                }
                self = provider
            case .local:
                return nil
            }
        }

        // ToS 회색 지대 경고 필요 여부
        public var requiresWarning: Bool {
            guard let providerID else { return false }
            return LLMProviderRegistry.shared.descriptor(for: providerID)?.requiresWarning ?? false
        }
    }

    public static let shared = LLMCorrectionService()
    private init() {}

    @AppStorage("llmProvider") public var selectedProvider: Provider = .none

    // 교정 진행 중 카운터 (ViewModel에서 UI 인디케이터에 사용)
    @Published public var activeCorrections: Int = 0

    func selectedTextProvider() -> (any LLMTextGenerationProvider)? {
        guard let providerID = selectedProvider.providerID else { return nil }
        return LLMProviderRegistry.shared.textGenerationProvider(for: providerID)
    }

    // MARK: - Correct

    /// 비동기 교정 수행. 실패 시 nil 반환 (원본 유지).
    public func correct(text: String, context: String) async -> String? {
        guard selectedProvider != .none, !text.isEmpty else { return nil }

        activeCorrections += 1
        defer { activeCorrections -= 1 }

        // 회의 맥락 + 직전 발화 + 현재 인식을 한 곳에서 프롬프트로 조립 (provider 공통)
        let meeting = MeetingContext.shared
        let (instructions, userContent) = CorrectionPrompt.build(
            topic: meeting.topic,
            glossary: meeting.glossary,
            context: context,
            text: text,
            summary: meeting.runningSummary,
            document: meeting.document
        )

        guard let provider = selectedTextProvider() else { return nil }

        fputs("[LLM] correcting via \(provider.descriptor.id.rawValue) (inputChars=\(text.count), contextChars=\(context.count))\n", stderr)
        do {
            let response = try await provider.generateText(LLMTextRequest(
                useCase: .correction,
                instructions: instructions,
                userContent: userContent
            ))
            let corrected = response.text
            fputs("[LLM] correction completed via \(provider.descriptor.id.rawValue) (outputChars=\(corrected.count))\n", stderr)
            return corrected
        } catch {
            fputs("[LLM] correction failed via \(provider.descriptor.id.rawValue): \(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    // MARK: - Auth helpers

    public var isLoggedIn: Bool {
        switch selectedProvider {
        case .none:
            return false
        case .gptAPI:
            return LLMAPIKeyStore.shared.hasAPIKey(for: .gpt)
        case .geminiAPI:
            return LLMAPIKeyStore.shared.hasAPIKey(for: .gemini)
        case .claudeAPI:
            return LLMAPIKeyStore.shared.hasAPIKey(for: .claude)
        case .openRouterAPI:
            return LLMAPIKeyStore.shared.hasAPIKey(for: .openRouter)
        case .gemini:
            return GeminiOAuthService.shared.isLoggedIn
        case .copilot:
            return CopilotOAuthService.shared.isLoggedIn
        case .codex:
            return CodexOAuthService.shared.isLoggedIn
        }
    }

    public var loginEmail: String {
        switch selectedProvider {
        case .none, .gptAPI, .geminiAPI, .claudeAPI, .openRouterAPI, .codex:
            return ""
        case .gemini:
            return GeminiOAuthService.shared.email
        case .copilot:
            return CopilotOAuthService.shared.email
        }
    }

    public func logout() {
        switch selectedProvider {
        case .none:
            break
        case .gptAPI:
            LLMAPIKeyStore.shared.deleteAPIKey(for: .gpt)
        case .geminiAPI:
            LLMAPIKeyStore.shared.deleteAPIKey(for: .gemini)
        case .claudeAPI:
            LLMAPIKeyStore.shared.deleteAPIKey(for: .claude)
        case .openRouterAPI:
            LLMAPIKeyStore.shared.deleteAPIKey(for: .openRouter)
        case .gemini:
            GeminiOAuthService.shared.logout()
        case .copilot:
            CopilotOAuthService.shared.logout()
        case .codex:
            CodexOAuthService.shared.logout()
        }
    }
}

// AppStorage에서 enum을 쓰기 위한 RawRepresentable 준수 (String으로 저장)
extension LLMCorrectionService.Provider: RawRepresentable {}
