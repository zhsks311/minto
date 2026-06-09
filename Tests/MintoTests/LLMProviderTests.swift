import Foundation
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

        #expect(LLMProviderSelection.local.providerID == .local)
        #expect(LLMProviderSelection(providerID: .local) == .local)
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

    @Test("로컬 provider는 text generation과 embedding capability를 노출한다")
    func localProviderExposesTextAndEmbeddingCapabilities() {
        let descriptor = LLMProviderRegistry.shared.descriptor(for: .local)

        #expect(descriptor?.supportedCapabilities == [.textGeneration, .correction, .summary, .answer, .embedding])
        #expect(LLMProviderRegistry.shared.textGenerationProvider(for: .local) != nil)
        #expect(LLMProviderRegistry.shared.embeddingProvider(for: .local) != nil)
    }

    @Test("로컬 LLM provider는 모델 ID가 있어야 설정 완료로 본다")
    func localLLMProviderRequiresModelID() async {
        let unconfigured = LocalLLMProvider(configuration: LocalLLMProviderConfiguration(modelID: ""))
        #expect(await unconfigured.isConfigured() == false)

        let configured = LocalLLMProvider(configuration: LocalLLMProviderConfiguration(modelID: "llama3.1:8b"))
        #expect(await configured.isConfigured())

        let catalog = await configured.modelCatalog()
        #expect(catalog.source == .manualOnly)
        #expect(catalog.models.first?.id == "llama3.1:8b")
        #expect(catalog.models.first?.capabilities == [.textGeneration, .correction, .summary, .answer])
    }

    @Test("로컬 LLM 설정은 저장값을 우선하고 환경변수를 fallback으로 쓴다")
    func localLLMConfigurationReadsStoredSettingsBeforeEnvironment() throws {
        let suiteName = "LocalLLMProviderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let environment = [
            "MINTO_LOCAL_LLM_BASE_URL": "http://127.0.0.1:11434",
            "MINTO_LOCAL_LLM_MODEL": "env-model",
            "MINTO_LOCAL_LLM_COMPATIBILITY": "ollamaGenerate",
            "MINTO_LOCAL_LLM_TIMEOUT_SECONDS": "90",
            "MINTO_LOCAL_LLM_CONTEXT_WINDOW": "8192"
        ]

        var configuration = LocalLLMProviderConfiguration.stored(defaults: defaults, environment: environment)
        #expect(configuration.baseURL.absoluteString == "http://127.0.0.1:11434")
        #expect(configuration.modelID == "env-model")
        #expect(configuration.compatibility == .ollamaGenerate)
        #expect(configuration.timeoutSeconds == 90)
        #expect(configuration.contextWindow == 8_192)

        defaults.set("http://127.0.0.1:8080", forKey: LocalLLMProviderConfiguration.baseURLKey)
        defaults.set("qwen2.5:7b", forKey: LocalLLMProviderConfiguration.modelIDKey)
        defaults.set(LocalLLMEndpointCompatibility.openAIChatCompletions.rawValue, forKey: LocalLLMProviderConfiguration.compatibilityKey)
        defaults.set(30.0, forKey: LocalLLMProviderConfiguration.timeoutSecondsKey)
        defaults.set(2_048, forKey: LocalLLMProviderConfiguration.contextWindowKey)

        configuration = LocalLLMProviderConfiguration.stored(defaults: defaults, environment: environment)
        #expect(configuration.baseURL.absoluteString == "http://127.0.0.1:8080")
        #expect(configuration.modelID == "qwen2.5:7b")
        #expect(configuration.compatibility == .openAIChatCompletions)
        #expect(configuration.timeoutSeconds == 30)
        #expect(configuration.contextWindow == 2_048)
        #expect(configuration.isConfigured)
    }

    @Test("로컬 LLM context window는 안전 범위로 제한된다")
    func localLLMConfigurationClampsContextWindow() {
        let tooSmall = LocalLLMProviderConfiguration(modelID: "local", contextWindow: 64)
        let tooLarge = LocalLLMProviderConfiguration(modelID: "local", contextWindow: 131_072)

        #expect(tooSmall.contextWindow == LocalLLMProviderConfiguration.minimumContextWindow)
        #expect(tooLarge.contextWindow == LocalLLMProviderConfiguration.maximumContextWindow)
    }

    @MainActor
    @Test("Settings 저장 local LLM 값은 교정, 요약, 검색 답변 provider로 연결된다")
    func localLLMSettingsRouteThroughAppProviderSelections() async throws {
        let defaults = UserDefaults.standard
        let localKeys = [
            LocalLLMProviderConfiguration.baseURLKey,
            LocalLLMProviderConfiguration.modelIDKey,
            LocalLLMProviderConfiguration.compatibilityKey,
            LocalLLMProviderConfiguration.timeoutSecondsKey,
            LocalLLMProviderConfiguration.contextWindowKey
        ]
        let savedDefaults = Dictionary(uniqueKeysWithValues: localKeys.map { ($0, defaults.object(forKey: $0)) })
        let savedCorrectionProvider = LLMCorrectionService.shared.selectedProvider
        let savedSummaryEnabled = LLMSummarySettingsService.shared.isEnabled
        let savedSummaryProvider = LLMSummarySettingsService.shared.selectedProvider
        let savedAnswerEnabled = MeetingSearchAnswerSettingsService.shared.isEnabled
        let savedAnswerProvider = MeetingSearchAnswerSettingsService.shared.selectedProvider
        defer {
            for key in localKeys {
                switch savedDefaults[key] {
                case .some(.some(let value)):
                    defaults.set(value, forKey: key)
                default:
                    defaults.removeObject(forKey: key)
                }
            }
            LLMCorrectionService.shared.selectedProvider = savedCorrectionProvider
            LLMSummarySettingsService.shared.isEnabled = savedSummaryEnabled
            LLMSummarySettingsService.shared.selectedProvider = savedSummaryProvider
            MeetingSearchAnswerSettingsService.shared.isEnabled = savedAnswerEnabled
            MeetingSearchAnswerSettingsService.shared.selectedProvider = savedAnswerProvider
        }

        defaults.set("http://127.0.0.1:11434", forKey: LocalLLMProviderConfiguration.baseURLKey)
        defaults.set("settings-local-model", forKey: LocalLLMProviderConfiguration.modelIDKey)
        defaults.set(LocalLLMEndpointCompatibility.ollamaGenerate.rawValue, forKey: LocalLLMProviderConfiguration.compatibilityKey)
        defaults.set(45.0, forKey: LocalLLMProviderConfiguration.timeoutSecondsKey)
        defaults.set(4_096, forKey: LocalLLMProviderConfiguration.contextWindowKey)
        LLMCorrectionService.shared.selectedProvider = .local
        LLMSummarySettingsService.shared.isEnabled = true
        LLMSummarySettingsService.shared.selectedProvider = .local
        MeetingSearchAnswerSettingsService.shared.isEnabled = true
        MeetingSearchAnswerSettingsService.shared.selectedProvider = .local

        #expect(LLMCorrectionService.shared.isLoggedIn)
        let correctionProvider = try #require(LLMCorrectionService.shared.selectedTextProvider())
        let summaryProvider = try #require(LLMSummarySettingsService.shared.selectedTextProvider())
        let answerProvider = try #require(MeetingSearchAnswerSettingsService.shared.selectedTextProvider())

        for provider in [correctionProvider, summaryProvider, answerProvider] {
            #expect(provider.descriptor.id == .local)
            #expect(await provider.isConfigured())
            let catalog = await provider.modelCatalog()
            #expect(catalog.models.first?.id == "settings-local-model")
            #expect(catalog.warning == nil)
        }
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
        #expect(gptAPIProvider?.descriptor.id == .gpt)

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

    @Test("API key 공급자는 키 미설정 시 기본 모델 카탈로그를 제공한다")
    func apiKeyProviderCatalogFallbackWithoutKey() async throws {
        let provider = try #require(LLMAPIKeyTextProvider(
            providerID: .claude,
            keyProvider: StubAPIKeyProvider(keys: [:]),
            transport: StubLLMAPITransport(data: Data("{}".utf8))
        ))

        #expect(await provider.isConfigured() == false)
        let catalog = await provider.modelCatalog()
        #expect(catalog.source == .bundledFallback)
        #expect(catalog.models.first?.id == "claude-sonnet-4-20250514")
        #expect(catalog.manualModelHelpURL != nil)
        #expect(catalog.warning?.contains("API 키") == true)
    }

    @Test("OpenAI API provider는 Responses API 요청을 만든다")
    func openAIAPIProviderBuildsResponsesRequest() async throws {
        let transport = StubLLMAPITransport(data: Data(#"{"output_text":"정리됨","model":"gpt-test"}"#.utf8))
        let provider = try #require(LLMAPIKeyTextProvider(
            providerID: .gpt,
            keyProvider: StubAPIKeyProvider(keys: [.gpt: "sk-test"]),
            transport: transport
        ))

        let response = try await provider.generateText(LLMTextRequest(
            useCase: .correction,
            instructions: "규칙",
            userContent: "원문",
            modelID: "gpt-test"
        ))

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(response.text == "정리됨")
        #expect(response.modelID == "gpt-test")

        let body = try Self.jsonObject(from: try #require(request.httpBody))
        #expect(body["model"] as? String == "gpt-test")
        #expect(body["instructions"] as? String == "규칙")
        #expect(body["input"] as? String == "원문")
        #expect(body["store"] as? Bool == false)
    }

    @Test("API key provider HTTP 상태는 공통 오류로 매핑된다")
    func apiKeyProviderMapsHTTPStatus() async throws {
        let provider = try #require(LLMAPIKeyTextProvider(
            providerID: .openRouter,
            keyProvider: StubAPIKeyProvider(keys: [.openRouter: "or-test"]),
            transport: StubLLMAPITransport(data: Data("rate limit".utf8), statusCode: 429)
        ))

        await #expect(throws: LLMProviderError.rateLimited) {
            _ = try await provider.generateText(LLMTextRequest(
                useCase: .answer,
                instructions: "답변",
                userContent: "질문",
                modelID: "openai/gpt-5.2"
            ))
        }
    }

    @Test("API key provider 모델 목록 인증 실패는 사용자가 알 수 있는 경고로 표시된다")
    func apiKeyProviderCatalogUnauthorizedWarning() async throws {
        let provider = try #require(LLMAPIKeyTextProvider(
            providerID: .gpt,
            keyProvider: StubAPIKeyProvider(keys: [.gpt: "sk-test"]),
            transport: StubLLMAPITransport(data: Data("unauthorized".utf8), statusCode: 401)
        ))

        let catalog = await provider.modelCatalog()
        #expect(catalog.source == .bundledFallback)
        #expect(catalog.warning?.contains("API 키") == true)
        #expect(catalog.warning?.contains("권한") == true)
    }

    @Test("API key provider 네트워크 오류는 공통 오류로 매핑된다")
    func apiKeyProviderMapsTransportError() async throws {
        let provider = try #require(LLMAPIKeyTextProvider(
            providerID: .gpt,
            keyProvider: StubAPIKeyProvider(keys: [.gpt: "sk-test"]),
            transport: StubLLMAPITransport(error: StubTransportError())
        ))

        await #expect(throws: LLMProviderError.network("timeout")) {
            _ = try await provider.generateText(LLMTextRequest(
                useCase: .correction,
                instructions: "규칙",
                userContent: "원문",
                modelID: "gpt-test"
            ))
        }
    }

    @Test("API key provider 요청 취소는 네트워크 오류로 바꾸지 않는다")
    func apiKeyProviderKeepsCancellationError() async throws {
        let provider = try #require(LLMAPIKeyTextProvider(
            providerID: .gpt,
            keyProvider: StubAPIKeyProvider(keys: [.gpt: "sk-test"]),
            transport: StubLLMAPITransport(error: CancellationError())
        ))

        var caughtCancellation = false
        do {
            _ = try await provider.generateText(LLMTextRequest(
                useCase: .answer,
                instructions: "규칙",
                userContent: "질문",
                modelID: "gpt-test"
            ))
        } catch is CancellationError {
            caughtCancellation = true
        }
        #expect(caughtCancellation)
    }

    @Test("로컬 LLM provider는 Ollama generate 요청을 만들고 응답을 파싱한다")
    func localLLMProviderBuildsOllamaGenerateRequest() async throws {
        let transport = StubLLMAPITransport(data: Data(#"{"model":"llama3.1:8b","response":"정리됨","done":true,"done_reason":"stop"}"#.utf8))
        let provider = LocalLLMProvider(
            configuration: LocalLLMProviderConfiguration(
                baseURL: URL(string: "http://127.0.0.1:11434")!,
                modelID: "llama3.1:8b",
                compatibility: .ollamaGenerate,
                contextWindow: 2_048
            ),
            transport: transport
        )

        let response = try await provider.generateText(LLMTextRequest(
            useCase: .finalSummary,
            instructions: "회의를 구조화하세요.",
            userContent: "회의 원문",
            modelID: nil
        ))

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/generate")
        #expect(request.httpMethod == "POST")
        #expect(response.text == "정리됨")
        #expect(response.providerID == .local)
        #expect(response.modelID == "llama3.1:8b")
        #expect(response.finishReason == .stop)

        let body = try Self.jsonObject(from: try #require(request.httpBody))
        #expect(body["model"] as? String == "llama3.1:8b")
        #expect(body["system"] as? String == "회의를 구조화하세요.")
        #expect(body["prompt"] as? String == "회의 원문")
        #expect(body["stream"] as? Bool == false)
        let options = try #require(body["options"] as? [String: Any])
        #expect(options["num_predict"] as? Int == 3_000)
        #expect(options["num_ctx"] as? Int == 2_048)
    }

    @Test("로컬 LLM provider는 OpenAI 호환 chat completions endpoint를 지원한다")
    func localLLMProviderBuildsOpenAICompatibleRequest() async throws {
        let transport = StubLLMAPITransport(data: Data(#"{"model":"qwen2.5:7b","choices":[{"message":{"content":"답변입니다. [1]"},"finish_reason":"length"}]}"#.utf8))
        let provider = LocalLLMProvider(
            configuration: LocalLLMProviderConfiguration(
                baseURL: URL(string: "http://127.0.0.1:8080")!,
                modelID: "qwen2.5:7b",
                compatibility: .openAIChatCompletions
            ),
            transport: transport
        )

        let response = try await provider.generateText(LLMTextRequest(
            useCase: .answer,
            instructions: "근거로만 답하세요.",
            userContent: "질문과 근거",
            modelID: "manual-model"
        ))

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:8080/v1/chat/completions")
        #expect(response.text == "답변입니다. [1]")
        #expect(response.modelID == "qwen2.5:7b")
        #expect(response.finishReason == .length)

        let body = try Self.jsonObject(from: try #require(request.httpBody))
        #expect(body["model"] as? String == "manual-model")
        #expect(body["max_tokens"] as? Int == 1_800)
        #expect(body["options"] == nil)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.first?["role"] == "system")
        #expect(messages.first?["content"] == "근거로만 답하세요.")
        #expect(messages.last?["role"] == "user")
        #expect(messages.last?["content"] == "질문과 근거")
    }

    @Test("로컬 LLM endpoint 실패는 prompt 원문 없이 공통 오류로 정규화한다")
    func localLLMProviderMapsEndpointFailureWithoutPromptBody() async throws {
        let echoedPrompt = "회의 원문이 포함된 서버 오류"
        let transport = StubLLMAPITransport(data: Data(echoedPrompt.utf8), statusCode: 500)
        let provider = LocalLLMProvider(
            configuration: LocalLLMProviderConfiguration(modelID: "llama3.1:8b"),
            transport: transport
        )

        do {
            _ = try await provider.generateText(LLMTextRequest(
                useCase: .correction,
                instructions: "규칙",
                userContent: "회의 원문"
            ))
            Issue.record("로컬 endpoint 실패가 오류로 반환되어야 합니다.")
        } catch let error as LLMProviderError {
            #expect(error == .network("로컬 LLM endpoint HTTP 500"))
            if case .network(let message) = error {
                #expect(!message.contains("회의 원문"))
            }
        }
    }

    @Test("로컬 LLM provider 네트워크 오류는 공통 network 오류로 매핑된다")
    func localLLMProviderMapsTransportError() async throws {
        let provider = LocalLLMProvider(
            configuration: LocalLLMProviderConfiguration(modelID: "llama3.1:8b"),
            transport: StubLLMAPITransport(error: StubTransportError())
        )

        await #expect(throws: LLMProviderError.network("timeout")) {
            _ = try await provider.generateText(LLMTextRequest(
                useCase: .answer,
                instructions: "답변",
                userContent: "질문"
            ))
        }
    }

    @Test("API key 저장소는 OAuth와 다른 Keychain service namespace를 쓴다")
    func apiKeyStoreUsesDedicatedKeychainNamespace() {
        #expect(KeychainService.llmAPIService == "com.minto.app.llm-api")
    }

    @Test("API key 존재 확인은 비밀값을 로드하지 않는다")
    func apiKeyStoreChecksExistenceWithoutLoadingSecret() {
        let storage = StubAPIKeyStorageBackend(loadData: Data("sk-test".utf8), existsResult: true)
        let store = LLMAPIKeyStore(serviceName: "test-llm-api", storage: storage)

        #expect(store.hasAPIKey(for: .gpt))
        #expect(storage.existsCallCount == 1)
        #expect(storage.loadCallCount == 0)

        #expect(store.apiKey(for: .gpt) == "sk-test")
        #expect(storage.loadCallCount == 1)
    }

    @Test("API key item이 있어도 빈 값이면 상태 cache를 미설정으로 내린다")
    func apiKeyStoreInvalidStoredValueClearsKnownStatusAfterLoad() {
        let storage = StubAPIKeyStorageBackend(loadData: Data("   ".utf8), existsResult: true)
        let store = LLMAPIKeyStore(serviceName: "test-llm-api", storage: storage)

        #expect(store.hasAPIKey(for: .gpt))
        #expect(store.apiKey(for: .gpt) == nil)
        #expect(store.hasAPIKey(for: .gpt) == false)
    }

    @Test("API key 저장 실패는 cache를 저장됨 상태로 갱신하지 않는다")
    func apiKeyStoreDoesNotCacheFailedSave() {
        let storage = StubAPIKeyStorageBackend(loadData: nil, saveResult: false)
        let store = LLMAPIKeyStore(serviceName: "test-llm-api", storage: storage)

        #expect(store.saveAPIKey("sk-test", for: .gpt) == false)
        #expect(store.apiKey(for: .gpt) == nil)
        #expect(store.hasAPIKey(for: .gpt) == false)
    }

    @Test("API key 삭제 실패는 cache를 삭제됨 상태로 갱신하지 않는다")
    func apiKeyStoreDoesNotClearCacheOnFailedDelete() {
        let storage = StubAPIKeyStorageBackend(loadData: Data("sk-test".utf8), deleteResult: false)
        let store = LLMAPIKeyStore(serviceName: "test-llm-api", storage: storage)

        #expect(store.apiKey(for: .gpt) == "sk-test")
        #expect(store.deleteAPIKey(for: .gpt) == false)
        #expect(store.apiKey(for: .gpt) == "sk-test")
    }

    @Test("API key 저장과 삭제 성공은 변경 notification을 보낸다")
    func apiKeyStorePostsChangeNotificationOnSuccess() {
        let center = NotificationCenter()
        let storage = StubAPIKeyStorageBackend(loadData: nil)
        let store = LLMAPIKeyStore(serviceName: "test-llm-api", storage: storage, notificationCenter: center)
        nonisolated(unsafe) var providers: [String] = []
        let observer = center.addObserver(forName: .llmAPIKeyStoreDidChange, object: nil, queue: nil) { notification in
            if let providerID = notification.userInfo?["providerID"] as? String {
                providers.append(providerID)
            }
        }
        defer { center.removeObserver(observer) }

        #expect(store.saveAPIKey("sk-test", for: .gpt))
        #expect(store.deleteAPIKey(for: .gpt))

        #expect(providers == [LLMProviderID.gpt.rawValue, LLMProviderID.gpt.rawValue])
    }

    @Test("API key 저장 실패는 변경 notification을 보내지 않는다")
    func apiKeyStoreDoesNotPostChangeNotificationOnFailedSave() {
        let center = NotificationCenter()
        let storage = StubAPIKeyStorageBackend(loadData: nil, saveResult: false)
        let store = LLMAPIKeyStore(serviceName: "test-llm-api", storage: storage, notificationCenter: center)
        nonisolated(unsafe) var notificationCount = 0
        let observer = center.addObserver(forName: .llmAPIKeyStoreDidChange, object: nil, queue: nil) { _ in
            notificationCount += 1
        }
        defer { center.removeObserver(observer) }

        #expect(store.saveAPIKey("sk-test", for: .gpt) == false)
        #expect(notificationCount == 0)
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private struct StubAPIKeyProvider: LLMAPIKeyProviding {
    let keys: [LLMProviderID: String]

    func apiKey(for providerID: LLMProviderID) -> String? {
        keys[providerID]
    }

    func hasAPIKey(for providerID: LLMProviderID) -> Bool {
        keys[providerID] != nil
    }
}

private final class StubLLMAPITransport: LLMAPITransport, @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private let statusCode: Int
    private let error: (any Error)?
    private(set) var requests: [URLRequest] = []

    init(data: Data = Data("{}".utf8), statusCode: Int = 200, error: (any Error)? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let error {
            throw error
        }
        lock.withLock {
            requests.append(request)
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private struct StubTransportError: LocalizedError {
    var errorDescription: String? { "timeout" }
}

private final class StubAPIKeyStorageBackend: LLMAPIKeyStorageBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let loadData: Data?
    private let existsResult: Bool
    private let saveResult: Bool
    private let deleteResult: Bool
    private(set) var existsCallCount = 0
    private(set) var loadCallCount = 0

    init(loadData: Data?, existsResult: Bool? = nil, saveResult: Bool = true, deleteResult: Bool = true) {
        self.loadData = loadData
        self.existsResult = existsResult ?? (loadData != nil)
        self.saveResult = saveResult
        self.deleteResult = deleteResult
    }

    func exists(account: String, service: String) -> Bool {
        lock.withLock {
            existsCallCount += 1
        }
        return existsResult
    }

    func load(account: String, service: String) -> Data? {
        lock.withLock {
            loadCallCount += 1
        }
        return loadData
    }

    func save(account: String, data: Data, service: String) -> Bool {
        saveResult
    }

    func delete(account: String, service: String) -> Bool {
        deleteResult
    }
}
