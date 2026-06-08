import Foundation

/// LLM을 사용하는 앱 기능. Provider adapter는 이 값으로 교정/요약/답변 요청을 구분한다.
public enum LLMUseCase: String, Codable, CaseIterable, Hashable, Sendable {
    case correction
    case summary
    case answer
}

/// 사용자에게 보여줄 LLM 공급자 단위.
public enum LLMProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case local
    case gpt
    case gemini
    case claude
    case openRouter
    case copilot
    case chatGPTAccount

    public var displayName: String {
        switch self {
        case .local:
            return "로컬 LLM"
        case .gpt:
            return "GPT"
        case .gemini:
            return "Gemini"
        case .claude:
            return "Claude"
        case .openRouter:
            return "OpenRouter"
        case .copilot:
            return "GitHub Copilot"
        case .chatGPTAccount:
            return "GPT 계정 로그인"
        }
    }

    public var isCloudProvider: Bool {
        switch self {
        case .local:
            return false
        case .gpt, .gemini, .claude, .openRouter, .copilot, .chatGPTAccount:
            return true
        }
    }
}

/// 설정 화면에서 모델을 사람 말로 설명하기 위한 표준 모델 정보.
public struct LLMModelInfo: Identifiable, Equatable, Sendable {
    public enum Capability: String, Codable, CaseIterable, Hashable, Sendable {
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

public struct LLMRequest: Sendable {
    public let useCase: LLMUseCase
    public let instructions: String
    public let userContent: String
    public let modelID: String?

    public init(useCase: LLMUseCase, instructions: String, userContent: String, modelID: String? = nil) {
        self.useCase = useCase
        self.instructions = instructions
        self.userContent = userContent
        self.modelID = modelID
    }
}

public struct LLMResponse: Sendable, Equatable {
    public let text: String
    public let modelID: String

    public init(text: String, modelID: String) {
        self.text = text
        self.modelID = modelID
    }
}

public enum LLMProviderError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    case modelUnavailable(String)
    case rateLimited
    case network(String)
    case badResponse(String)

    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "공급자 설정이 필요합니다."
        case .unauthorized:
            return "인증이 만료되었거나 권한이 없습니다."
        case .modelUnavailable(let model):
            return "선택한 모델을 사용할 수 없습니다: \(model)"
        case .rateLimited:
            return "요청 한도에 도달했습니다. 잠시 후 다시 시도하세요."
        case .network:
            return "네트워크 연결을 확인하세요."
        case .badResponse:
            return "공급자 응답을 이해하지 못했습니다."
        }
    }
}

public protocol LLMProvider: Sendable {
    var id: LLMProviderID { get }
    var isConfigured: Bool { get }

    func listModels() async throws -> [LLMModelInfo]
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}
