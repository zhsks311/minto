import Foundation

public enum LocalLLMEndpointCompatibility: String, CaseIterable, Identifiable, Sendable {
    case ollamaGenerate
    case openAIChatCompletions

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollamaGenerate:
            return "Ollama"
        case .openAIChatCompletions:
            return "기타 OpenAI 호환 서버"
        }
    }
}

public struct LocalLLMProviderConfiguration: Equatable, Sendable {
    public static let baseURLKey = "localLLMBaseURL"
    public static let modelIDKey = "localLLMModelID"
    public static let compatibilityKey = "localLLMCompatibility"
    public static let timeoutSecondsKey = "localLLMTimeoutSeconds"
    public static let contextWindowKey = "localLLMContextWindow"
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:11434")!
    public static let defaultTimeoutSeconds: TimeInterval = 120
    public static let defaultContextWindow = 4_608
    public static let minimumContextWindow = 512
    public static let maximumContextWindow = 32_768

    public let baseURL: URL
    public let modelID: String
    public let compatibility: LocalLLMEndpointCompatibility
    public let timeoutSeconds: TimeInterval
    public let contextWindow: Int

    public init(
        baseURL: URL = Self.defaultBaseURL,
        modelID: String = "",
        compatibility: LocalLLMEndpointCompatibility = .ollamaGenerate,
        timeoutSeconds: TimeInterval = Self.defaultTimeoutSeconds,
        contextWindow: Int = Self.defaultContextWindow
    ) {
        self.baseURL = baseURL
        self.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.compatibility = compatibility
        self.timeoutSeconds = max(5, timeoutSeconds)
        self.contextWindow = Self.clampedContextWindow(contextWindow)
    }

    public var isConfigured: Bool {
        !modelID.isEmpty
    }

    public static func environment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        let baseURL = endpointURL(from: environment["MINTO_LOCAL_LLM_BASE_URL"]) ?? defaultBaseURL
        let modelID = environment["MINTO_LOCAL_LLM_MODEL"] ?? ""
        let timeoutSeconds = environment["MINTO_LOCAL_LLM_TIMEOUT_SECONDS"]
            .flatMap(TimeInterval.init)
            ?? defaultTimeoutSeconds
        let contextWindow = environment["MINTO_LOCAL_LLM_CONTEXT_WINDOW"]
            .flatMap(Int.init)
            ?? defaultContextWindow
        let compatibility = Self.compatibility(from: environment["MINTO_LOCAL_LLM_COMPATIBILITY"])
        return Self(
            baseURL: baseURL,
            modelID: modelID,
            compatibility: compatibility,
            timeoutSeconds: timeoutSeconds,
            contextWindow: contextWindow
        )
    }

    public static func stored(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        let environmentConfiguration = Self.environment(environment)
        let savedBaseURL = endpointURL(from: defaults.string(forKey: baseURLKey))
        let savedModelID = nonEmpty(defaults.string(forKey: modelIDKey))
        let savedCompatibility = defaults.string(forKey: compatibilityKey)
        let savedCompatibilityValue = savedCompatibility.map(compatibility(from:))
        let savedTimeout = defaults.object(forKey: timeoutSecondsKey) as? TimeInterval
        let savedContextWindow = defaults.object(forKey: contextWindowKey) as? Int

        return Self(
            baseURL: savedBaseURL ?? environmentConfiguration.baseURL,
            modelID: savedModelID ?? environmentConfiguration.modelID,
            compatibility: savedCompatibilityValue ?? environmentConfiguration.compatibility,
            timeoutSeconds: savedTimeout ?? environmentConfiguration.timeoutSeconds,
            contextWindow: savedContextWindow ?? environmentConfiguration.contextWindow
        )
    }

    public static func compatibility(from rawValue: String?) -> LocalLLMEndpointCompatibility {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case LocalLLMEndpointCompatibility.openAIChatCompletions.rawValue.lowercased(),
             "openai",
             "openai_chat",
             "openai-chat",
             "chat_completions",
             "chat-completions",
             "llama.cpp":
            return .openAIChatCompletions
        default:
            return .ollamaGenerate
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func endpointURL(from value: String?) -> URL? {
        guard let rawValue = nonEmpty(value),
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            return nil
        }
        return url
    }

    private static func clampedContextWindow(_ value: Int) -> Int {
        min(max(value, minimumContextWindow), maximumContextWindow)
    }
}

public final class LocalLLMProvider: LLMTextGenerationProvider, @unchecked Sendable {
    public let descriptor: LLMProviderDescriptor

    private let configuration: LocalLLMProviderConfiguration
    private let transport: any LLMAPITransport

    public init(
        registry: LLMProviderRegistry = .shared,
        configuration: LocalLLMProviderConfiguration = .stored(),
        transport: any LLMAPITransport = URLSessionLLMAPITransport()
    ) {
        self.descriptor = registry.descriptor(for: .local) ?? LLMProviderDescriptor(
            id: .local,
            description: "외부 로컬 런타임으로 교정, 요약, 검색 답변과 기기 내 검색을 실행합니다.",
            authKind: .local,
            supportedCapabilities: [.textGeneration, .correction, .summary, .answer, .embedding]
        )
        self.configuration = configuration
        self.transport = transport
    }

    public func isConfigured() async -> Bool {
        configuration.isConfigured
    }

    public func modelCatalog() async -> LLMModelCatalog {
        if configuration.compatibility == .ollamaGenerate {
            return await ollamaModelCatalog()
        }
        return manualModelCatalog(warning: openAICompatibleModelWarning())
    }

    private func ollamaModelCatalog() async -> LLMModelCatalog {
        var request = URLRequest(
            url: configuration.baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("tags")
        )
        request.httpMethod = "GET"
        request.timeoutInterval = min(configuration.timeoutSeconds, 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await transport.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                return manualModelCatalog(warning: "Ollama 설치 모델 조회 실패: HTTP \(response.statusCode)")
            }
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return manualModelCatalog(warning: "Ollama 모델 목록 응답을 이해하지 못했습니다.")
            }

            let installedModels = ollamaModels(from: payload)
            let warning = ollamaCatalogWarning(for: installedModels)
            return LLMModelCatalog(
                models: installedModels,
                source: .live,
                warning: warning
            )
        } catch is CancellationError {
            return manualModelCatalog(warning: "Ollama 설치 모델 조회가 취소되었습니다.")
        } catch {
            return manualModelCatalog(warning: "Ollama 설치 모델을 확인하지 못했습니다. endpoint와 Ollama 실행 상태를 확인하세요.")
        }
    }

    private func manualModelCatalog(warning: String? = nil) -> LLMModelCatalog {
        let textCapabilities: Set<LLMModelInfo.Capability> = [.textGeneration, .correction, .summary, .answer]
        let models: [LLMModelInfo]
        if configuration.modelID.isEmpty {
            models = []
        } else {
            models = [
                LLMModelInfo(
                    id: configuration.modelID,
                    displayName: configuration.modelID,
                    description: "외부 로컬 런타임에서 제공하는 수동 설정 모델입니다.",
                    capabilities: textCapabilities,
                    isRecommended: false
                )
            ]
        }
        return LLMModelCatalog(
            models: models,
            source: .manualOnly,
            warning: warning ?? (configuration.modelID.isEmpty ? "로컬 LLM endpoint와 모델 ID를 설정해야 합니다." : nil)
        )
    }

    private func ollamaModels(from payload: [String: Any]) -> [LLMModelInfo] {
        let rawModels = payload["models"] as? [[String: Any]] ?? []
        return rawModels.compactMap { rawModel in
            let id = (
                rawModel["name"] as? String
                ?? rawModel["model"] as? String
                ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }

            let details = rawModel["details"] as? [String: Any] ?? [:]
            let parameterSize = details["parameter_size"] as? String
            let quantization = details["quantization_level"] as? String
            let sizeDescription = (rawModel["size"] as? NSNumber)
                .map { Self.formattedByteCount($0.int64Value) }
            let description = [
                parameterSize.map { "parameters \($0)" },
                quantization.map { "quantization \($0)" },
                sizeDescription.map { "size \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")

            return LLMModelInfo(
                id: id,
                displayName: id,
                description: description,
                capabilities: [.textGeneration, .correction, .summary, .answer],
                isRecommended: id == configuration.modelID
            )
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private func ollamaCatalogWarning(for installedModels: [LLMModelInfo]) -> String? {
        if installedModels.isEmpty {
            return "Ollama에 설치된 모델이 없습니다. 터미널에서 ollama pull <model>을 실행하세요."
        }
        guard !configuration.modelID.isEmpty else {
            return "설치된 모델을 선택하거나 모델 ID를 입력하세요."
        }
        let installedModelIDs = Set(installedModels.map(\.id))
        if !installedModelIDs.contains(configuration.modelID) {
            return "입력한 모델 ID가 Ollama 설치 목록에 없습니다: \(configuration.modelID)"
        }
        return nil
    }

    private func openAICompatibleModelWarning() -> String? {
        if configuration.modelID.isEmpty {
            return "OpenAI 호환 런타임에서 사용할 모델 ID를 입력하세요."
        }
        return "OpenAI 호환 런타임은 표준 설치 모델 목록 API가 없어 모델 ID를 직접 입력합니다."
    }

    private static func formattedByteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    public func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        let modelID = selectedModelID(requestModelID: request.modelID)
        guard !modelID.isEmpty else {
            throw LLMProviderError.notConfigured
        }

        let urlRequest = try makeURLRequest(for: request, modelID: modelID)
        let json = try await sendJSON(urlRequest, modelID: modelID)
        let text = extractText(from: json).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LLMProviderError.badResponse("빈 로컬 LLM 응답")
        }

        return LLMTextResponse(
            text: text,
            providerID: .local,
            modelID: json["model"] as? String ?? modelID,
            finishReason: finishReason(from: json)
        )
    }

    private func selectedModelID(requestModelID: String?) -> String {
        let requestModelID = requestModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return requestModelID.isEmpty ? configuration.modelID : requestModelID
    }

    private func makeURLRequest(for request: LLMTextRequest, modelID: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: endpointURL())
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody(for: request, modelID: modelID))
        return urlRequest
    }

    private func endpointURL() -> URL {
        switch configuration.compatibility {
        case .ollamaGenerate:
            return configuration.baseURL.appendingPathComponent("api").appendingPathComponent("generate")
        case .openAIChatCompletions:
            return configuration.baseURL.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")
        }
    }

    private func requestBody(for request: LLMTextRequest, modelID: String) -> [String: Any] {
        switch configuration.compatibility {
        case .ollamaGenerate:
            return [
                "model": modelID,
                "system": request.instructions,
                "prompt": request.userContent,
                "stream": false,
                "options": [
                    "temperature": 0.1,
                    "num_predict": maxOutputTokens(for: request),
                    "num_ctx": configuration.contextWindow
                ]
            ]
        case .openAIChatCompletions:
            return [
                "model": modelID,
                "messages": [
                    ["role": "system", "content": request.instructions],
                    ["role": "user", "content": request.userContent]
                ],
                "temperature": 0.1,
                "max_tokens": maxOutputTokens(for: request),
                "stream": false
            ]
        }
    }

    private func sendJSON(_ request: URLRequest, modelID: String) async throws -> [String: Any] {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as LLMProviderError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LLMProviderError.network(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw providerError(statusCode: response.statusCode, modelID: modelID)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.badResponse("로컬 LLM JSON 객체가 아닙니다.")
        }
        return json
    }

    private func providerError(statusCode: Int, modelID: String) -> LLMProviderError {
        switch statusCode {
        case 404:
            return .modelUnavailable(modelID)
        case 408, 500...599:
            return .network("로컬 LLM endpoint HTTP \(statusCode)")
        default:
            return .httpStatus(statusCode, "로컬 LLM endpoint HTTP \(statusCode)")
        }
    }

    private func extractText(from json: [String: Any]) -> String {
        switch configuration.compatibility {
        case .ollamaGenerate:
            return json["response"] as? String ?? ""
        case .openAIChatCompletions:
            guard let message = firstChoice(in: json)?["message"] as? [String: Any] else { return "" }
            if let content = message["content"] as? String {
                return content
            }
            let contentParts = message["content"] as? [[String: Any]] ?? []
            return contentParts.compactMap { $0["text"] as? String }.joined()
        }
    }

    private func finishReason(from json: [String: Any]) -> LLMTextResponse.FinishReason {
        switch configuration.compatibility {
        case .ollamaGenerate:
            switch json["done_reason"] as? String {
            case "stop":
                return .stop
            case "length":
                return .length
            default:
                return (json["done"] as? Bool) == true ? .stop : .unknown
            }
        case .openAIChatCompletions:
            switch firstChoice(in: json)?["finish_reason"] as? String {
            case "stop":
                return .stop
            case "length":
                return .length
            default:
                return .unknown
            }
        }
    }

    private func firstChoice(in json: [String: Any]) -> [String: Any]? {
        let choices = json["choices"] as? [[String: Any]] ?? []
        return choices.first
    }

    private func maxOutputTokens(for request: LLMTextRequest) -> Int {
        if let maxOutputTokens = request.maxOutputTokens {
            return max(1, maxOutputTokens)
        }
        return maxOutputTokens(for: request.useCase)
    }

    private func maxOutputTokens(for useCase: LLMUseCase) -> Int {
        switch useCase {
        case .correction:
            return 900
        case .incrementalSummary:
            return 1_200
        case .finalSummary:
            return 3_000
        case .answer:
            return 1_800
        }
    }
}

// MARK: - LLMEmbeddingProvider (Ollama 전용)

extension LocalLLMProvider: LLMEmbeddingProvider {
    /// Ollama `/api/embeddings` 엔드포인트를 통해 임베딩을 생성한다.
    /// `openAIChatCompletions` 호환 모드이거나 modelID가 설정되지 않은 경우 `.notConfigured` throw —
    /// 호출측에서 LocalHashEmbeddingProvider로 fallback한다.
    public func generateEmbedding(_ request: LLMEmbeddingRequest) async throws -> LLMEmbeddingResponse {
        guard configuration.compatibility == .ollamaGenerate else {
            throw LLMProviderError.notConfigured
        }
        let modelID = selectedModelID(requestModelID: request.modelID)
        guard !modelID.isEmpty else {
            throw LLMProviderError.notConfigured
        }

        let url = configuration.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("embeddings")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = min(configuration.timeoutSeconds, 30)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "prompt": request.input
        ])

        let json = try await sendJSON(urlRequest, modelID: modelID)
        guard let rawVector = json["embedding"] as? [Double], !rawVector.isEmpty else {
            throw LLMProviderError.badResponse("ollama 임베딩 응답에 embedding 배열이 없습니다.")
        }

        return LLMEmbeddingResponse(
            vector: rawVector,
            providerID: .local,
            modelID: modelID,
            sourceID: request.sourceID,
            kind: .semantic
        )
    }
}
