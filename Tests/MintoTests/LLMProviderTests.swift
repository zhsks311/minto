import Testing
@testable import MintoCore

@Suite("LLMProvider 공통 타입", .serialized)
struct LLMProviderTests {

    @Test("공급자 표시 이름은 사용자 용어를 사용한다")
    func providerDisplayNames() {
        let names = Dictionary(uniqueKeysWithValues: LLMProviderID.allCases.map { ($0, $0.displayName) })

        #expect(names[.local] == "로컬 LLM")
        #expect(names[.gpt] == "GPT API")
        #expect(names[.gemini] == "Gemini API")
        #expect(names[.claude] == "Claude API")
        #expect(names[.openRouter] == "OpenRouter API")
        #expect(names[.copilot] == "GitHub Copilot 계정")
        #expect(names[.chatGPTAccount] == "GPT 계정 로그인")
        #expect(names[.geminiAccount] == "Gemini 계정 로그인")
    }

    @Test("로컬 공급자와 클라우드 공급자를 구분한다")
    func providerCloudClassification() {
        for providerID in LLMProviderID.allCases {
            #expect(providerID.isCloudProvider == (providerID != .local))
        }
    }

    @Test("공급자 오류는 사용자에게 보여줄 메시지를 가진다")
    func providerErrorMessages() {
        let notConfigured = LLMProviderError.notConfigured
        let modelUnavailable = LLMProviderError.modelUnavailable("gpt-x")
        let rateLimited = LLMProviderError.rateLimited

        #expect(notConfigured.userMessage == "공급자 설정이 필요합니다.")
        #expect(notConfigured.localizedDescription == notConfigured.userMessage)
        #expect(modelUnavailable.userMessage.contains("gpt-x"))
        #expect(rateLimited.userMessage.contains("요청 한도"))
        #expect(rateLimited.isRetryable)
        #expect(rateLimited.statusCode == 429)
    }

    @Test("legacy 교정 설정은 새 공급자 ID로 매핑된다")
    func legacyCorrectionProviderMapping() {
        let registry = LLMProviderRegistry.shared

        #expect(registry.providerID(forLegacyCorrectionProviderRawValue: "codex") == .chatGPTAccount)
        #expect(registry.providerID(forLegacyCorrectionProviderRawValue: "gemini") == .geminiAccount)
        #expect(registry.providerID(forLegacyCorrectionProviderRawValue: "copilot") == .copilot)
        #expect(registry.legacyCorrectionProviderRawValue(for: .gpt) == nil)
        #expect(LLMCorrectionService.Provider(providerID: .chatGPTAccount) == .codex)
        #expect(LLMCorrectionService.Provider.codex.providerID == .chatGPTAccount)
        #expect(LLMCorrectionService.Provider.gemini.requiresWarning)
        #expect(!LLMCorrectionService.Provider.copilot.requiresWarning)
    }

    @Test("생성 모델과 임베딩 모델 계약은 분리되어 있다")
    func generationAndEmbeddingContractsAreSeparate() {
        let textResponse = LLMTextResponse(text: "ok", providerID: .local, modelID: "local")
        let embeddingResponse = LLMEmbeddingResponse(vector: [0.1, 0.2], providerID: .local, modelID: "embed")

        #expect(textResponse.text == "ok")
        #expect(embeddingResponse.vector == [0.1, 0.2])
    }

    @MainActor
    @Test("legacy 계정 공급자는 text generation adapter로 생성된다")
    func legacyAccountTextProviderCreation() async {
        let registry = LLMProviderRegistry.shared
        let chatGPTProvider = registry.textGenerationProvider(for: .chatGPTAccount)
        let geminiProvider = registry.textGenerationProvider(for: .geminiAccount)
        let copilotProvider = registry.textGenerationProvider(for: .copilot)
        let gptAPIProvider = registry.textGenerationProvider(for: .gpt)

        #expect(chatGPTProvider?.descriptor.id == .chatGPTAccount)
        #expect(geminiProvider?.descriptor.id == .geminiAccount)
        #expect(copilotProvider?.descriptor.id == .copilot)
        #expect(gptAPIProvider == nil)

        let catalog = await chatGPTProvider?.modelCatalog()
        #expect(catalog?.source == .bundledFallback)
        #expect(catalog?.models.isEmpty == false)
    }

    @MainActor
    @Test("교정 서비스의 legacy 선택값은 text adapter로 연결된다")
    func correctionServiceSelectedProviderResolvesToAdapter() {
        let saved = LLMCorrectionService.shared.selectedProvider
        defer { LLMCorrectionService.shared.selectedProvider = saved }

        LLMCorrectionService.shared.selectedProvider = .codex
        #expect(LLMCorrectionService.shared.selectedTextProvider()?.descriptor.id == .chatGPTAccount)

        LLMCorrectionService.shared.selectedProvider = .none
        #expect(LLMCorrectionService.shared.selectedTextProvider() == nil)
    }
}
