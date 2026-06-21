import os
import Foundation

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
    public typealias TextProviderResolver = @MainActor (LLMProviderID) -> (any LLMTextGenerationProvider)?

    public static let shared = LLMCorrectionService()
    public static let selectedProviderKey = "llmProvider"

    private let defaults: UserDefaults

    /// UserDefaults + @Published 단방향 저장이다. 같은 키를 다른 곳에서 @AppStorage로 바인딩하면 역동기화가 깨진다.
    @Published public var selectedProvider: Provider {
        didSet {
            defaults.set(selectedProvider.rawValue, forKey: Self.selectedProviderKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawProvider = defaults.string(forKey: Self.selectedProviderKey),
           let provider = Provider(rawValue: rawProvider) {
            selectedProvider = provider
        } else {
            selectedProvider = .none
        }
    }

    // 교정 진행 중 카운터 (ViewModel에서 UI 인디케이터에 사용)
    @Published public var activeCorrections: Int = 0

    func selectedTextProvider(
        providerResolver: TextProviderResolver? = nil
    ) -> (any LLMTextGenerationProvider)? {
        guard let providerID = selectedProvider.providerID else { return nil }
        let provider = providerResolver?(providerID)
            ?? LLMProviderRegistry.shared.textGenerationProvider(for: providerID)
        guard provider?.descriptor.supportedCapabilities.contains(.correction) == true else { return nil }
        return provider
    }

    // MARK: - Correct

    /// 비동기 교정 수행. 실패 시 nil 반환 (원본 유지).
    public func correct(text: String, context: String) async -> String? {
        let meeting = MeetingContext.shared
        return await correct(
            text: text,
            context: LLMCorrectionContext(
                topic: meeting.topic,
                glossary: meeting.glossaryForPrompt,
                previousText: context,
                runningSummary: meeting.runningSummary,
                document: meeting.document
            )
        )
    }

    /// 명시적 context로 교정한다. 파일 import처럼 live `MeetingContext`를 섞으면 안 되는 경로에서 사용한다.
    public func correct(text: String, context: LLMCorrectionContext) async -> String? {
        await correct(text: text, context: context, providerResolver: nil)
    }

    /// 명시적 context와 provider resolver로 교정한다. 테스트에서 registry 전역 상태를 우회할 때 사용한다.
    public func correct(
        text: String,
        context: LLMCorrectionContext,
        providerResolver: TextProviderResolver? = nil
    ) async -> String? {
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

        guard let provider = selectedTextProvider(providerResolver: providerResolver) else { return nil }

        Log.correction.info("correcting via \(provider.descriptor.id.rawValue, privacy: .public) inputChars=\(text.count, privacy: .public) contextChars=\(context.previousText.count, privacy: .public) documentChars=\(context.document.count, privacy: .public)")
        do {
            let response = try await provider.generateText(LLMTextRequest(
                useCase: .correction,
                instructions: instructions,
                userContent: userContent
            ))
            let corrected = CorrectionOutputPostprocessor.clean(response.text)
            let aliasPairs = CorrectionAliasExtractor.extract(raw: text, corrected: corrected)
            Log.correction.debug("correction alias extraction pairs=\(aliasPairs.count, privacy: .public)")
            if !aliasPairs.isEmpty {
                GlossaryStore.shared.ingestCorrectionAliases(aliasPairs)
            }
            Log.correction.info("correction completed via \(provider.descriptor.id.rawValue, privacy: .public) outputChars=\(corrected.count, privacy: .public)")
            return corrected
        } catch {
            Log.correction.error("correction failed via \(provider.descriptor.id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Batch Correct

    /// 여러 텍스트를 한 번의 LLM 호출로 배치 교정한다.
    /// 파싱 실패 또는 provider 오류 시 nil 반환 — 호출부가 원문 유지(fail-soft)를 담당한다.
    public func correctBatch(texts: [String], context: LLMCorrectionContext) async -> [String?]? {
        await correctBatch(texts: texts, context: context, providerResolver: nil)
    }

    func correctBatch(
        texts: [String],
        context: LLMCorrectionContext,
        providerResolver: TextProviderResolver? = nil
    ) async -> [String?]? {
        guard selectedProvider != .none, !texts.isEmpty else { return nil }

        activeCorrections += 1
        defer { activeCorrections -= 1 }

        let (instructions, userContent) = BatchCorrectionPrompt.build(
            texts: texts,
            topic: context.topic,
            glossary: context.glossary,
            context: context.previousText,
            summary: context.runningSummary,
            document: context.document
        )

        guard let provider = selectedTextProvider(providerResolver: providerResolver) else { return nil }

        let maxTokens = 900 * texts.count
        Log.correction.info("correctBatch via \(provider.descriptor.id.rawValue, privacy: .public) batchSize=\(texts.count, privacy: .public) documentChars=\(context.document.count, privacy: .public)")
        do {
            let response = try await provider.generateText(LLMTextRequest(
                useCase: .correction,
                instructions: instructions,
                userContent: userContent,
                maxOutputTokens: maxTokens
            ))
            let parsed = BatchCorrectionPrompt.parse(response: response.text, expectedCount: texts.count)
            if parsed == nil {
                Log.correction.info("correctBatch parse failed batchSize=\(texts.count, privacy: .public)")
            } else {
                Log.correction.info("correctBatch completed via \(provider.descriptor.id.rawValue, privacy: .public) batchSize=\(texts.count, privacy: .public)")
            }
            return parsed
        } catch {
            Log.correction.error("correctBatch failed via \(provider.descriptor.id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
