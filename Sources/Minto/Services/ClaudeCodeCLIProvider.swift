import Foundation

public final class ClaudeCodeCLIProvider: LLMTextGenerationProvider, @unchecked Sendable {
    public static let cliPathKey = "claudeCodeCLIPath"
    public static let modelDefaultsKey = "claudeCodeCLIModel"
    public static let defaultModelID = "sonnet"

    public let descriptor: LLMProviderDescriptor
    private let defaults: UserDefaults

    public init?(registry: LLMProviderRegistry = .shared, defaults: UserDefaults = .standard) {
        guard let descriptor = registry.descriptor(for: .claudeCodeCLI),
              descriptor.authKind == .cliPath
        else {
            return nil
        }
        self.descriptor = descriptor
        self.defaults = defaults
    }

    public func isConfigured() async -> Bool {
        Self.cliPathExists(defaults.string(forKey: Self.cliPathKey) ?? "")
    }

    public func modelCatalog() async -> LLMModelCatalog {
        Self.bundledModelCatalog()
    }

    public func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        guard await isConfigured() else { throw LLMProviderError.notConfigured }
        _ = selectedModelID(requestModelID: request.modelID)
        throw LLMProviderError.badResponse("Claude Code CLI 호출은 Phase 2에서 구현됩니다.")
    }

    public static func bundledModelCatalog() -> LLMModelCatalog {
        LLMModelCatalog(
            models: bundledModels(),
            source: .bundledFallback,
            manualModelHelpURL: URL(string: "https://docs.anthropic.com/en/docs/about-claude/models/overview"),
            warning: "Claude Code CLI는 이 Mac의 claude 로그인을 사용하지만 회의 내용은 Anthropic으로 전송돼요."
        )
    }

    public static func bundledModels() -> [LLMModelInfo] {
        let capabilities: Set<LLMModelInfo.Capability> = [.textGeneration, .summary, .answer]
        return [
            LLMModelInfo(
                id: "sonnet",
                displayName: "Claude Sonnet",
                description: "회의록 정리와 검색 답변의 기본 선택",
                capabilities: capabilities,
                isRecommended: true
            ),
            LLMModelInfo(
                id: "opus",
                displayName: "Claude Opus",
                description: "복잡한 회의 구조화 품질을 우선할 때",
                capabilities: capabilities
            ),
            LLMModelInfo(
                id: "haiku",
                displayName: "Claude Haiku",
                description: "짧은 답변과 낮은 지연 시간을 우선할 때",
                capabilities: capabilities
            )
        ]
    }

    public static func cliPathExists(_ rawPath: String, fileManager: FileManager = .default) -> Bool {
        let path = normalizedCLIPath(rawPath)
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    public static func normalizedCLIPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("~") else { return trimmed }
        return (trimmed as NSString).expandingTildeInPath
    }

    private func selectedModelID(requestModelID: String?) -> String {
        if let requestModelID, !requestModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return requestModelID
        }
        let saved = defaults.string(forKey: Self.modelDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? Self.defaultModelID : saved
    }
}
