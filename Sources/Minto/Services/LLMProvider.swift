import Foundation

/// LLM을 사용하는 앱 기능. Provider adapter는 이 값으로 교정/요약/답변 요청을 구분한다.
public enum LLMUseCase: String, Codable, CaseIterable, Hashable, Sendable {
    case correction
    case incrementalSummary
    case finalSummary
    case answer
    /// 첨부 문서를 회의 요약용 참고 맥락으로 1회 압축(plain 불릿). 전사 요약과 별도 토큰·라우팅·로그로 구분한다.
    case documentSummary
}

/// 사용자에게 보여줄 LLM 공급자 단위.
public enum LLMProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case local
    case gpt
    case gemini
    case claude
    case claudeCodeCLI
    case openRouter
    case copilot
    case chatGPTAccount
    case geminiAccount

    public var displayName: String {
        switch self {
        case .local:
            return "로컬 LLM"
        case .gpt:
            return "GPT API"
        case .gemini:
            return "Gemini API"
        case .claude:
            return "Claude API"
        case .claudeCodeCLI:
            return "Claude Code CLI"
        case .openRouter:
            return "OpenRouter API"
        case .copilot:
            return "GitHub Copilot 계정"
        case .chatGPTAccount:
            return "GPT 계정 로그인"
        case .geminiAccount:
            return "Gemini 계정 로그인"
        }
    }

    public var isCloudProvider: Bool {
        switch self {
        case .local:
            return false
        case .gpt, .gemini, .claude, .claudeCodeCLI, .openRouter, .copilot, .chatGPTAccount, .geminiAccount:
            return true
        }
    }
}

public enum LLMProviderAuthKind: String, Codable, Sendable {
    case local
    case apiKey
    case accountLogin
    case cliPath
}

public enum LLMModelCatalogSource: String, Codable, Sendable {
    case live
    case bundledFallback
    case manualOnly
}

/// 설정 화면에서 모델을 사람 말로 설명하기 위한 표준 모델 정보.
public struct LLMModelInfo: Identifiable, Equatable, Sendable {
    public enum Capability: String, Codable, CaseIterable, Hashable, Sendable {
        case textGeneration
        case correction
        case summary
        case answer
        case embedding
    }

    public let id: String
    public let displayName: String
    public let description: String
    public let capabilities: Set<Capability>
    public let isRecommended: Bool
    public let ramRequirement: String?
    public let contextWindow: Int?

    public init(
        id: String,
        displayName: String,
        description: String = "",
        capabilities: Set<Capability> = [],
        isRecommended: Bool = false,
        ramRequirement: String? = nil,
        contextWindow: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.capabilities = capabilities
        self.isRecommended = isRecommended
        self.ramRequirement = ramRequirement
        self.contextWindow = contextWindow
    }
}

public struct LLMProviderDescriptor: Identifiable, Equatable, Sendable {
    public let id: LLMProviderID
    public let displayName: String
    public let description: String
    public let authKind: LLMProviderAuthKind
    public let requiresWarning: Bool
    public let supportedCapabilities: Set<LLMModelInfo.Capability>

    public init(
        id: LLMProviderID,
        displayName: String? = nil,
        description: String,
        authKind: LLMProviderAuthKind,
        requiresWarning: Bool = false,
        supportedCapabilities: Set<LLMModelInfo.Capability>
    ) {
        self.id = id
        self.displayName = displayName ?? id.displayName
        self.description = description
        self.authKind = authKind
        self.requiresWarning = requiresWarning
        self.supportedCapabilities = supportedCapabilities
    }
}

public struct LLMModelCatalog: Equatable, Sendable {
    public let models: [LLMModelInfo]
    public let source: LLMModelCatalogSource
    public let manualModelHelpURL: URL?
    public let warning: String?

    public init(
        models: [LLMModelInfo],
        source: LLMModelCatalogSource,
        manualModelHelpURL: URL? = nil,
        warning: String? = nil
    ) {
        self.models = models
        self.source = source
        self.manualModelHelpURL = manualModelHelpURL
        self.warning = warning
    }
}

public struct LLMTextRequest: Sendable {
    public let useCase: LLMUseCase
    public let instructions: String
    public let userContent: String
    public let modelID: String?
    public let maxOutputTokens: Int?

    public init(
        useCase: LLMUseCase,
        instructions: String,
        userContent: String,
        modelID: String? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.useCase = useCase
        self.instructions = instructions
        self.userContent = userContent
        self.modelID = modelID
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct LLMTextResponse: Equatable, Sendable {
    public enum FinishReason: String, Codable, Sendable {
        case stop
        case length
        case cancelled
        case unknown
    }

    public let text: String
    public let providerID: LLMProviderID
    public let modelID: String
    public let finishReason: FinishReason
    public let warnings: [String]

    public init(
        text: String,
        providerID: LLMProviderID,
        modelID: String,
        finishReason: FinishReason = .unknown,
        warnings: [String] = []
    ) {
        self.text = text
        self.providerID = providerID
        self.modelID = modelID
        self.finishReason = finishReason
        self.warnings = warnings
    }
}

public struct LLMEmbeddingRequest: Sendable {
    public let input: String
    public let modelID: String?
    public let sourceID: String?

    public init(input: String, modelID: String? = nil, sourceID: String? = nil) {
        self.input = input
        self.modelID = modelID
        self.sourceID = sourceID
    }
}

public enum LLMEmbeddingKind: String, Codable, Sendable {
    case semantic
    case lexicalHash
}

public struct LLMEmbeddingResponse: Equatable, Sendable {
    public let vector: [Double]
    public let providerID: LLMProviderID
    public let modelID: String
    public let sourceID: String?
    public let kind: LLMEmbeddingKind

    public init(
        vector: [Double],
        providerID: LLMProviderID,
        modelID: String,
        sourceID: String? = nil,
        kind: LLMEmbeddingKind = .semantic
    ) {
        self.vector = vector
        self.providerID = providerID
        self.modelID = modelID
        self.sourceID = sourceID
        self.kind = kind
    }
}

public enum LLMProviderError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    case modelUnavailable(String)
    case rateLimited
    case network(String)
    case badResponse(String)
    case httpStatus(Int, String)

    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "공급자 설정이 필요해요."
        case .unauthorized:
            return "인증이 만료되었거나 권한이 없어요."
        case .modelUnavailable(let model):
            return "선택한 모델을 사용할 수 없어요: \(model)"
        case .rateLimited:
            return "요청 한도에 도달했어요. 잠시 후 다시 시도하세요."
        case .network:
            return "네트워크 연결을 확인하세요."
        case .badResponse:
            return "공급자 응답을 이해하지 못했어요."
        case .httpStatus(let statusCode, _):
            return "공급자 요청이 실패했어요. HTTP \(statusCode)"
        }
    }

    public var userAction: String? {
        switch self {
        case .notConfigured:
            return "설정에서 공급자와 모델을 선택하세요."
        case .unauthorized:
            return "다시 로그인하거나 API 키를 확인하세요."
        case .modelUnavailable:
            return "다른 모델을 선택하거나 모델 이름을 확인하세요."
        case .rateLimited:
            return "잠시 후 다시 시도하거나 호출 빈도를 낮추세요."
        case .network:
            return "인터넷 연결과 방화벽 설정을 확인하세요."
        case .badResponse:
            return "다른 모델로 다시 시도하세요."
        case .httpStatus(let statusCode, _):
            return statusCode == 429 ? "잠시 후 다시 시도하세요." : "공급자 설정과 권한을 확인하세요."
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .network:
            return true
        case .httpStatus(let statusCode, _):
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        case .notConfigured, .unauthorized, .modelUnavailable, .badResponse:
            return false
        }
    }

    public var statusCode: Int? {
        if case .httpStatus(let statusCode, _) = self {
            return statusCode
        }
        if case .rateLimited = self {
            return 429
        }
        return nil
    }
}

extension LLMProviderError: LocalizedError {
    public var errorDescription: String? { userMessage }
    public var recoverySuggestion: String? { userAction }
}

public protocol LLMModelCatalogProvider: Sendable {
    var descriptor: LLMProviderDescriptor { get }

    func isConfigured() async -> Bool
    func modelCatalog() async -> LLMModelCatalog
}

public protocol LLMTextGenerationProvider: LLMModelCatalogProvider {
    func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse
}

public protocol LLMEmbeddingProvider: LLMModelCatalogProvider {
    func generateEmbedding(_ request: LLMEmbeddingRequest) async throws -> LLMEmbeddingResponse
}
