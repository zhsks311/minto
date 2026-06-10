import os
import Foundation
import SwiftUI

public struct LLMCorrectionContext: Sendable, Equatable {
    public let topic: String
    public let glossary: String
    public let previousText: String
    public let runningSummary: String
    public let document: String

    public init(
        topic: String = "",
        glossary: String = "",
        previousText: String = "",
        runningSummary: String = "",
        document: String = ""
    ) {
        self.topic = topic
        self.glossary = glossary
        self.previousText = previousText
        self.runningSummary = runningSummary
        self.document = document
    }
}

@MainActor
public final class LLMCorrectionService: ObservableObject {

    public typealias Provider = LLMProviderSelection

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
        let meeting = MeetingContext.shared
        return await correct(
            text: text,
            context: LLMCorrectionContext(
                topic: meeting.topic,
                glossary: meeting.glossary,
                previousText: context,
                runningSummary: meeting.runningSummary,
                document: meeting.document
            )
        )
    }

    /// 명시적 context로 교정한다. 파일 import처럼 live `MeetingContext`를 섞으면 안 되는 경로에서 사용한다.
    public func correct(text: String, context: LLMCorrectionContext) async -> String? {
        guard selectedProvider != .none, !text.isEmpty else { return nil }

        activeCorrections += 1
        defer { activeCorrections -= 1 }

        let (instructions, userContent) = CorrectionPrompt.build(
            topic: context.topic,
            glossary: context.glossary,
            context: context.previousText,
            text: text,
            summary: context.runningSummary,
            document: context.document
        )

        guard let provider = selectedTextProvider() else { return nil }

        Log.correction.info("correcting via \(provider.descriptor.id.rawValue, privacy: .public) inputChars=\(text.count, privacy: .public) contextChars=\(context.previousText.count, privacy: .public)")
        do {
            let response = try await provider.generateText(LLMTextRequest(
                useCase: .correction,
                instructions: instructions,
                userContent: userContent
            ))
            let corrected = CorrectionOutputPostprocessor.clean(response.text)
            Log.correction.info("correction completed via \(provider.descriptor.id.rawValue, privacy: .public) outputChars=\(corrected.count, privacy: .public)")
            return corrected
        } catch {
            Log.correction.error("correction failed via \(provider.descriptor.id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Auth helpers

    public var isLoggedIn: Bool {
        switch selectedProvider {
        case .none:
            return false
        case .local:
            return LocalLLMProviderConfiguration.stored().isConfigured
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
        case .none, .local, .gptAPI, .geminiAPI, .claudeAPI, .openRouterAPI, .codex:
            return ""
        case .gemini:
            return GeminiOAuthService.shared.email
        case .copilot:
            return CopilotOAuthService.shared.email
        }
    }

    public func logout() {
        switch selectedProvider {
        case .none, .local:
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
