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

    @Test("로컬 provider는 구현된 embedding capability만 노출한다")
    func localProviderOnlyExposesImplementedCapabilities() {
        let descriptor = LLMProviderRegistry.shared.descriptor(for: .local)

        #expect(descriptor?.supportedCapabilities == [.embedding])
        #expect(LLMProviderRegistry.shared.textGenerationProvider(for: .local) == nil)
        #expect(LLMProviderRegistry.shared.embeddingProvider(for: .local) != nil)
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

    @Test("API key 저장소는 OAuth와 다른 Keychain service namespace를 쓴다")
    func apiKeyStoreUsesDedicatedKeychainNamespace() {
        #expect(KeychainService.llmAPIService == "com.minto.app.llm-api")
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
    private let loadData: Data?
    private let saveResult: Bool
    private let deleteResult: Bool

    init(loadData: Data?, saveResult: Bool = true, deleteResult: Bool = true) {
        self.loadData = loadData
        self.saveResult = saveResult
        self.deleteResult = deleteResult
    }

    func load(account: String, service: String) -> Data? {
        loadData
    }

    func save(account: String, data: Data, service: String) -> Bool {
        saveResult
    }

    func delete(account: String, service: String) -> Bool {
        deleteResult
    }
}
