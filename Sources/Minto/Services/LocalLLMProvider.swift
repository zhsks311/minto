import Foundation

public enum LocalLLMEndpointCompatibility: String, Sendable {
    case ollamaGenerate
    case openAIChatCompletions
}

public struct LocalLLMProviderConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let modelID: String
    public let compatibility: LocalLLMEndpointCompatibility
    public let timeoutSeconds: TimeInterval

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        modelID: String = "",
        compatibility: LocalLLMEndpointCompatibility = .ollamaGenerate,
        timeoutSeconds: TimeInterval = 120
    ) {
        self.baseURL = baseURL
        self.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.compatibility = compatibility
        self.timeoutSeconds = timeoutSeconds
    }

    public static func environment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        let baseURL = environment["MINTO_LOCAL_LLM_BASE_URL"]
            .flatMap(URL.init(string:))
            ?? URL(string: "http://127.0.0.1:11434")!
        let modelID = environment["MINTO_LOCAL_LLM_MODEL"] ?? ""
        let timeoutSeconds = environment["MINTO_LOCAL_LLM_TIMEOUT_SECONDS"]
            .flatMap(TimeInterval.init)
            ?? 120
        let compatibility = Self.compatibility(from: environment["MINTO_LOCAL_LLM_COMPATIBILITY"])
        return Self(
            baseURL: baseURL,
            modelID: modelID,
            compatibility: compatibility,
            timeoutSeconds: timeoutSeconds
        )
    }

    private static func compatibility(from rawValue: String?) -> LocalLLMEndpointCompatibility {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "openai", "openai_chat", "openai-chat", "chat_completions", "chat-completions", "llama.cpp":
            return .openAIChatCompletions
        default:
            return .ollamaGenerate
        }
    }
}

public final class LocalLLMProvider: LLMTextGenerationProvider, @unchecked Sendable {
    public let descriptor: LLMProviderDescriptor

    private let configuration: LocalLLMProviderConfiguration
    private let transport: any LLMAPITransport

    public init(
        registry: LLMProviderRegistry = .shared,
        configuration: LocalLLMProviderConfiguration = .environment(),
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
        !configuration.modelID.isEmpty
    }

    public func modelCatalog() async -> LLMModelCatalog {
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
            warning: configuration.modelID.isEmpty ? "로컬 LLM endpoint와 모델 ID를 설정해야 합니다." : nil
        )
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
                    "num_predict": maxOutputTokens(for: request.useCase)
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
                "max_tokens": maxOutputTokens(for: request.useCase),
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
