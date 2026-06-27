import Foundation

public protocol LLMAPITransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionLLMAPITransport: LLMAPITransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.badResponse("HTTP 응답이 아닙니다.")
        }
        return (data, httpResponse)
    }
}

public final class LLMAPIKeyTextProvider: LLMTextGenerationProvider, @unchecked Sendable {
    public let descriptor: LLMProviderDescriptor

    private let keyProvider: any LLMAPIKeyProviding
    private let transport: any LLMAPITransport
    private let defaults: UserDefaults

    public init?(
        providerID: LLMProviderID,
        registry: LLMProviderRegistry = .shared,
        keyProvider: any LLMAPIKeyProviding = LLMAPIKeyStore.shared,
        transport: any LLMAPITransport = URLSessionLLMAPITransport(),
        defaults: UserDefaults = .standard
    ) {
        guard let descriptor = registry.descriptor(for: providerID),
              descriptor.authKind == .apiKey,
              [.gpt, .gemini, .claude, .openRouter].contains(providerID)
        else {
            return nil
        }
        self.descriptor = descriptor
        self.keyProvider = keyProvider
        self.transport = transport
        self.defaults = defaults
    }

    public func isConfigured() async -> Bool {
        keyProvider.hasAPIKey(for: descriptor.id)
    }

    public func modelCatalog() async -> LLMModelCatalog {
        guard let apiKey = keyProvider.apiKey(for: descriptor.id) else {
            return Self.bundledModelCatalog(
                for: descriptor.id,
                source: .bundledFallback,
                warning: "API 키를 저장하면 사용 가능한 모델 목록을 자동으로 확인해요."
            )
        }

        do {
            let models = try await liveModels(apiKey: apiKey)
            guard !models.isEmpty else {
                return Self.bundledModelCatalog(
                    for: descriptor.id,
                    source: .bundledFallback,
                    warning: "모델 목록이 비어 있어 기본 추천 모델을 표시해요."
                )
            }
            return LLMModelCatalog(
                models: models,
                source: .live,
                manualModelHelpURL: Self.modelHelpURL(for: descriptor.id),
                warning: nil
            )
        } catch {
            return Self.bundledModelCatalog(
                for: descriptor.id,
                source: .bundledFallback,
                warning: Self.modelCatalogWarning(for: error)
            )
        }
    }

    public func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        guard let apiKey = keyProvider.apiKey(for: descriptor.id) else {
            throw LLMProviderError.notConfigured
        }

        switch descriptor.id {
        case .gpt:
            return try await generateOpenAIText(request, apiKey: apiKey)
        case .gemini:
            return try await generateGeminiText(request, apiKey: apiKey)
        case .claude:
            return try await generateClaudeText(request, apiKey: apiKey)
        case .openRouter:
            return try await generateOpenRouterText(request, apiKey: apiKey)
        case .local, .claudeCodeCLI, .copilot, .chatGPTAccount, .geminiAccount:
            throw LLMProviderError.notConfigured
        }
    }

    public static func modelDefaultsKey(for providerID: LLMProviderID) -> String {
        switch providerID {
        case .gpt:
            return "gptAPIModel"
        case .gemini:
            return "geminiAPIModel"
        case .claude:
            return "claudeAPIModel"
        case .openRouter:
            return "openRouterAPIModel"
        case .local, .claudeCodeCLI, .copilot, .chatGPTAccount, .geminiAccount:
            return ""
        }
    }

    public static func bundledModels(for providerID: LLMProviderID) -> [LLMModelInfo] {
        let textCapabilities: Set<LLMModelInfo.Capability> = [.textGeneration, .correction, .summary, .answer]
        switch providerID {
        case .gpt:
            return [
                LLMModelInfo(
                    id: "gpt-5.5",
                    displayName: "GPT-5.5",
                    description: "회의 교정과 요약 품질을 우선할 때",
                    capabilities: textCapabilities.union([.embedding]),
                    isRecommended: true
                ),
                LLMModelInfo(
                    id: "gpt-5.4",
                    displayName: "GPT-5.4",
                    description: "품질과 속도의 균형이 필요할 때",
                    capabilities: textCapabilities
                ),
                LLMModelInfo(
                    id: "gpt-5.4-mini",
                    displayName: "GPT-5.4 mini",
                    description: "비용과 속도를 더 중시할 때",
                    capabilities: textCapabilities
                )
            ]
        case .gemini:
            return [
                LLMModelInfo(
                    id: "gemini-3.5-flash",
                    displayName: "Gemini 3.5 Flash",
                    description: "빠른 회의 교정과 요약",
                    capabilities: textCapabilities,
                    isRecommended: true
                ),
                LLMModelInfo(
                    id: "gemini-3.1-pro-preview",
                    displayName: "Gemini 3.1 Pro Preview",
                    description: "긴 문맥과 높은 품질이 필요할 때",
                    capabilities: textCapabilities
                ),
                LLMModelInfo(
                    id: "gemini-3.1-flash-lite",
                    displayName: "Gemini 3.1 Flash-Lite",
                    description: "비용과 지연 시간을 낮출 때",
                    capabilities: textCapabilities
                )
            ]
        case .claude:
            return [
                LLMModelInfo(
                    id: "claude-sonnet-4-6",
                    displayName: "Claude Sonnet 4.6",
                    description: "긴 회의 맥락 정리와 구조화",
                    capabilities: textCapabilities,
                    isRecommended: true
                ),
                LLMModelInfo(
                    id: "claude-haiku-4-5-20251001",
                    displayName: "Claude Haiku 4.5",
                    description: "빠른 교정과 짧은 요약",
                    capabilities: textCapabilities
                ),
                LLMModelInfo(
                    id: "claude-opus-4-8",
                    displayName: "Claude Opus 4.8",
                    description: "복잡한 회의 구조화 품질을 우선할 때",
                    capabilities: textCapabilities
                ),
                LLMModelInfo(
                    id: "claude-fable-5",
                    displayName: "Claude Fable 5",
                    description: "최고 성능 모델을 직접 선택할 때",
                    capabilities: textCapabilities
                )
            ]
        case .openRouter:
            return [
                LLMModelInfo(
                    id: "openai/gpt-5.5",
                    displayName: "OpenAI GPT-5.5",
                    description: "OpenRouter를 통한 GPT 고품질 모델",
                    capabilities: textCapabilities,
                    isRecommended: true
                ),
                LLMModelInfo(
                    id: "anthropic/claude-sonnet-4.6",
                    displayName: "Claude Sonnet 4.6",
                    description: "긴 회의 구조화에 강한 모델",
                    capabilities: textCapabilities
                ),
                LLMModelInfo(
                    id: "google/gemini-3.5-flash",
                    displayName: "Gemini 3.5 Flash",
                    description: "빠른 교정과 요약",
                    capabilities: textCapabilities
                ),
                LLMModelInfo(
                    id: "openai/gpt-5.4-mini",
                    displayName: "OpenAI GPT-5.4 mini",
                    description: "비용과 속도를 낮출 때",
                    capabilities: textCapabilities
                )
            ]
        case .local, .claudeCodeCLI, .copilot, .chatGPTAccount, .geminiAccount:
            return []
        }
    }

    public static func bundledModelCatalog(
        for providerID: LLMProviderID,
        source: LLMModelCatalogSource = .bundledFallback,
        warning: String? = nil
    ) -> LLMModelCatalog {
        LLMModelCatalog(
            models: bundledModels(for: providerID),
            source: source,
            manualModelHelpURL: modelHelpURL(for: providerID),
            warning: warning
        )
    }

    public static func defaultModelID(for providerID: LLMProviderID) -> String {
        bundledModels(for: providerID).first(where: \.isRecommended)?.id
            ?? bundledModels(for: providerID).first?.id
            ?? ""
    }

    public static func modelHelpURL(for providerID: LLMProviderID) -> URL? {
        switch providerID {
        case .gpt:
            return URL(string: "https://platform.openai.com/docs/models")
        case .gemini:
            return URL(string: "https://ai.google.dev/gemini-api/docs/models")
        case .claude:
            return URL(string: "https://docs.anthropic.com/en/docs/about-claude/models/overview")
        case .openRouter:
            return URL(string: "https://openrouter.ai/models")
        case .local, .claudeCodeCLI, .copilot, .chatGPTAccount, .geminiAccount:
            return nil
        }
    }

    private func selectedModelID(requestModelID: String?) -> String {
        if let requestModelID, !requestModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return requestModelID
        }
        let key = Self.modelDefaultsKey(for: descriptor.id)
        let saved = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? Self.defaultModelID(for: descriptor.id) : saved
    }

    private func generateOpenAIText(_ request: LLMTextRequest, apiKey: String) async throws -> LLMTextResponse {
        let modelID = selectedModelID(requestModelID: request.modelID)
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "instructions": request.instructions,
            "input": request.userContent,
            "store": false,
            "max_output_tokens": maxOutputTokens(for: request)
        ])

        let json = try await sendJSON(urlRequest)
        let text = Self.extractOpenAIText(from: json)
        guard !text.isEmpty else { throw LLMProviderError.badResponse("빈 OpenAI 응답") }
        return LLMTextResponse(
            text: text,
            providerID: descriptor.id,
            modelID: json["model"] as? String ?? modelID,
            finishReason: .stop
        )
    }

    private func generateGeminiText(_ request: LLMTextRequest, apiKey: String) async throws -> LLMTextResponse {
        let modelID = selectedModelID(requestModelID: request.modelID).replacingOccurrences(of: "models/", with: "")
        let escapedModel = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID
        var urlRequest = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):generateContent")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": request.instructions]]],
            "contents": [["role": "user", "parts": [["text": request.userContent]]]],
            "generationConfig": geminiGenerationConfig(for: request)
        ])

        let json = try await sendJSON(urlRequest)
        let text = Self.extractGeminiText(from: json)
        guard !text.isEmpty else { throw LLMProviderError.badResponse("빈 Gemini 응답") }
        return LLMTextResponse(text: text, providerID: descriptor.id, modelID: modelID, finishReason: .stop)
    }

    private func generateClaudeText(_ request: LLMTextRequest, apiKey: String) async throws -> LLMTextResponse {
        let modelID = selectedModelID(requestModelID: request.modelID)
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "system": request.instructions,
            "max_tokens": maxOutputTokens(for: request),
            "temperature": 0.1,
            "messages": [["role": "user", "content": request.userContent]]
        ])

        let json = try await sendJSON(urlRequest)
        let text = Self.extractClaudeText(from: json)
        guard !text.isEmpty else { throw LLMProviderError.badResponse("빈 Claude 응답") }
        return LLMTextResponse(
            text: text,
            providerID: descriptor.id,
            modelID: json["model"] as? String ?? modelID,
            finishReason: Self.finishReason(from: json["stop_reason"] as? String)
        )
    }

    private func generateOpenRouterText(_ request: LLMTextRequest, apiKey: String) async throws -> LLMTextResponse {
        let modelID = selectedModelID(requestModelID: request.modelID)
        var urlRequest = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Minto", forHTTPHeaderField: "X-Title")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "max_tokens": maxOutputTokens(for: request),
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": request.instructions],
                ["role": "user", "content": request.userContent]
            ]
        ])

        let json = try await sendJSON(urlRequest)
        let text = Self.extractOpenAIChatText(from: json)
        guard !text.isEmpty else { throw LLMProviderError.badResponse("빈 OpenRouter 응답") }
        return LLMTextResponse(
            text: text,
            providerID: descriptor.id,
            modelID: json["model"] as? String ?? modelID,
            finishReason: Self.finishReason(from: Self.firstChoice(in: json)?["finish_reason"] as? String)
        )
    }

    private func liveModels(apiKey: String) async throws -> [LLMModelInfo] {
        switch descriptor.id {
        case .gpt:
            return try await liveOpenAIModels(apiKey: apiKey)
        case .gemini:
            return try await liveGeminiModels(apiKey: apiKey)
        case .claude:
            return try await liveClaudeModels(apiKey: apiKey)
        case .openRouter:
            return try await liveOpenRouterModels(apiKey: apiKey)
        case .local, .claudeCodeCLI, .copilot, .chatGPTAccount, .geminiAccount:
            return []
        }
    }

    private func liveOpenAIModels(apiKey: String) async throws -> [LLMModelInfo] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let json = try await sendJSON(request)
        let data = json["data"] as? [[String: Any]] ?? []
        return data.compactMap { item -> LLMModelInfo? in
            guard let id = item["id"] as? String, Self.isLikelyOpenAITextModel(id) else { return nil }
            return LLMModelInfo(
                id: id,
                displayName: id,
                capabilities: [.textGeneration, .correction, .summary, .answer],
                isRecommended: id == Self.defaultModelID(for: .gpt)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
            return lhs.id > rhs.id
        }
    }

    private func liveGeminiModels(apiKey: String) async throws -> [LLMModelInfo] {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let json = try await sendJSON(request)
        let models = json["models"] as? [[String: Any]] ?? []
        return models.compactMap { item -> LLMModelInfo? in
            guard let name = item["name"] as? String else { return nil }
            let methods = item["supportedGenerationMethods"] as? [String] ?? []
            guard methods.contains("generateContent") else { return nil }
            let id = name.replacingOccurrences(of: "models/", with: "")
            return LLMModelInfo(
                id: id,
                displayName: item["displayName"] as? String ?? id,
                description: item["description"] as? String ?? "",
                capabilities: [.textGeneration, .correction, .summary, .answer],
                isRecommended: id == Self.defaultModelID(for: .gemini),
                contextWindow: item["inputTokenLimit"] as? Int
            )
        }
    }

    private func liveClaudeModels(apiKey: String) async throws -> [LLMModelInfo] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let json = try await sendJSON(request)
        let data = json["data"] as? [[String: Any]] ?? []
        return data.compactMap { item -> LLMModelInfo? in
            guard let id = item["id"] as? String else { return nil }
            return LLMModelInfo(
                id: id,
                displayName: item["display_name"] as? String ?? id,
                capabilities: [.textGeneration, .correction, .summary, .answer],
                isRecommended: id == Self.defaultModelID(for: .claude)
            )
        }
    }

    private func liveOpenRouterModels(apiKey: String) async throws -> [LLMModelInfo] {
        var components = URLComponents(string: "https://openrouter.ai/api/v1/models")!
        components.queryItems = [URLQueryItem(name: "output_modalities", value: "text")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let json = try await sendJSON(request)
        let data = json["data"] as? [[String: Any]] ?? []
        return data.compactMap { item -> LLMModelInfo? in
            guard let id = item["id"] as? String else { return nil }
            return LLMModelInfo(
                id: id,
                displayName: item["name"] as? String ?? id,
                description: item["description"] as? String ?? "",
                capabilities: [.textGeneration, .correction, .summary, .answer],
                isRecommended: id == Self.defaultModelID(for: .openRouter),
                contextWindow: item["context_length"] as? Int
            )
        }
    }

    private func sendJSON(_ request: URLRequest) async throws -> [String: Any] {
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
            let body = String(data: data.prefix(800), encoding: .utf8) ?? ""
            throw Self.providerError(statusCode: response.statusCode, body: body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.badResponse("JSON 객체가 아닙니다.")
        }
        return json
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
        case .documentSummary:
            return 1_200
        }
    }

    private func geminiGenerationConfig(for request: LLMTextRequest) -> [String: Any] {
        var config: [String: Any] = [
            "temperature": 0.1,
            "maxOutputTokens": maxOutputTokens(for: request)
        ]
        if request.useCase == .finalSummary {
            config["responseFormat"] = Self.meetingSummaryResponseFormat()
        }
        return config
    }

    private static func meetingSummaryResponseFormat() -> [String: Any] {
        [
            "text": [
                "mimeType": "application/json",
                "schema": meetingSummarySchema()
            ]
        ]
    }

    private static func meetingSummarySchema() -> [String: Any] {
        let timedTextSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "text": ["type": "string"],
                "time": ["type": "string"]
            ],
            "required": ["text", "time"]
        ]
        let actionItemSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "task": ["type": "string"],
                "owner": ["type": "string"],
                "due": ["type": "string"],
                "time": ["type": "string"]
            ],
            "required": ["task", "owner", "due", "time"]
        ]
        let pointSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "text": ["type": "string"],
                "subPoints": [
                    "type": "array",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["text", "subPoints"]
        ]
        let sectionSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "time": ["type": "string"],
                "points": [
                    "type": "array",
                    "items": pointSchema
                ]
            ],
            "required": ["title", "time", "points"]
        ]

        return [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "leadQuestion": ["type": "string"],
                "leadAnswer": ["type": "string"],
                "decisions": [
                    "type": "array",
                    "items": timedTextSchema
                ],
                "actionItems": [
                    "type": "array",
                    "items": actionItemSchema
                ],
                "openQuestions": [
                    "type": "array",
                    "items": timedTextSchema
                ],
                "sections": [
                    "type": "array",
                    "items": sectionSchema
                ],
                "keywords": [
                    "type": "array",
                    "items": ["type": "string"]
                ]
            ],
            "required": [
                "title",
                "leadQuestion",
                "leadAnswer",
                "decisions",
                "actionItems",
                "openQuestions",
                "sections",
                "keywords"
            ]
        ]
    }

    private static func providerError(statusCode: Int, body: String) -> LLMProviderError {
        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 404:
            return .modelUnavailable(body)
        case 429:
            return .rateLimited
        default:
            return .httpStatus(statusCode, body)
        }
    }

    private static func modelCatalogWarning(for error: any Error) -> String {
        guard let providerError = error as? LLMProviderError else {
            return "모델 목록을 확인하지 못했어요. 네트워크 상태를 확인하거나 모델 ID를 직접 입력하세요."
        }
        switch providerError {
        case .unauthorized:
            return "API 키가 유효하지 않거나 권한이 없어요. API 키를 확인하세요."
        case .rateLimited:
            return "모델 목록 요청 한도에 도달했어요. 잠시 후 다시 시도하거나 모델 ID를 직접 입력하세요."
        case .network:
            return "모델 목록을 확인하지 못했어요. 네트워크 상태를 확인하거나 모델 ID를 직접 입력하세요."
        case .modelUnavailable:
            return "모델 목록을 확인하지 못했어요. 모델 확인 링크에서 ID를 확인해 직접 입력하세요."
        case .notConfigured:
            return "API 키를 저장하면 사용 가능한 모델 목록을 확인해요."
        case .badResponse, .httpStatus:
            return "공급자 응답을 이해하지 못해 기본 추천 모델을 표시해요. 모델 ID를 직접 입력할 수 있어요."
        }
    }

    private static func isLikelyOpenAITextModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        let excluded = ["embedding", "whisper", "tts", "dall-e", "image", "audio", "transcribe", "moderation", "realtime"]
        guard !excluded.contains(where: { lower.contains($0) }) else { return false }
        return lower.hasPrefix("gpt-") || lower.hasPrefix("o") || lower.hasPrefix("chatgpt-")
    }

    private static func extractOpenAIText(from json: [String: Any]) -> String {
        if let outputText = json["output_text"] as? String {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let output = json["output"] as? [[String: Any]] ?? []
        let parts = output.flatMap { item -> [String] in
            let content = item["content"] as? [[String: Any]] ?? []
            return content.compactMap { contentItem in
                contentItem["text"] as? String
            }
        }
        return parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractGeminiText(from json: [String: Any]) -> String {
        let candidates = json["candidates"] as? [[String: Any]] ?? []
        let content = candidates.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        return parts.compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractClaudeText(from json: [String: Any]) -> String {
        let content = json["content"] as? [[String: Any]] ?? []
        return content.compactMap { item -> String? in
            guard item["type"] as? String == "text" || item["type"] == nil else { return nil }
            return item["text"] as? String
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractOpenAIChatText(from json: [String: Any]) -> String {
        guard let message = firstChoice(in: json)?["message"] as? [String: Any] else { return "" }
        if let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let contentParts = message["content"] as? [[String: Any]] ?? []
        return contentParts.compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstChoice(in json: [String: Any]) -> [String: Any]? {
        let choices = json["choices"] as? [[String: Any]] ?? []
        return choices.first
    }

    private static func finishReason(from rawValue: String?) -> LLMTextResponse.FinishReason {
        switch rawValue {
        case "stop", "end_turn":
            return .stop
        case "length", "max_tokens":
            return .length
        default:
            return .unknown
        }
    }
}
