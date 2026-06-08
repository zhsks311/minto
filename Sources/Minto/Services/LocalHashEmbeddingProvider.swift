import Foundation

public struct LocalHashEmbeddingProvider: LLMEmbeddingProvider {
    public static let modelID = "minto-local-hash-embedding-v1"
    public static let dimensions = 128

    public let descriptor: LLMProviderDescriptor
    private let dimensions: Int

    public init(registry: LLMProviderRegistry = .shared, dimensions: Int = Self.dimensions) {
        self.descriptor = registry.descriptor(for: .local) ?? LLMProviderDescriptor(
            id: .local,
            description: "저장된 회의를 기기 안에서 검색할 때 사용합니다.",
            authKind: .local,
            supportedCapabilities: [.embedding]
        )
        self.dimensions = max(8, dimensions)
    }

    public func isConfigured() async -> Bool {
        true
    }

    public func modelCatalog() async -> LLMModelCatalog {
        LLMModelCatalog(
            models: [
                LLMModelInfo(
                    id: Self.modelID,
                    displayName: "기기 내 빠른 검색",
                    description: "의미 유사도 모델이 아닌 로컬 후보 검색용 벡터입니다.",
                    capabilities: [.embedding],
                    isRecommended: true,
                    ramRequirement: "매우 낮음",
                    contextWindow: nil
                )
            ],
            source: .bundledFallback
        )
    }

    public func generateEmbedding(_ request: LLMEmbeddingRequest) async throws -> LLMEmbeddingResponse {
        LLMEmbeddingResponse(
            vector: Self.vector(for: request.input, dimensions: dimensions),
            providerID: .local,
            modelID: request.modelID ?? Self.modelID,
            sourceID: request.sourceID,
            kind: .lexicalHash
        )
    }

    static func vector(for text: String, dimensions: Int = Self.dimensions) -> [Double] {
        let dims = max(8, dimensions)
        var vector = Array(repeating: 0.0, count: dims)
        for token in tokenize(text) {
            let hash = stableHash(token)
            let index = Int(hash % UInt64(dims))
            vector[index] += (hash & 1 == 0) ? 1 : -1
        }

        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    private static func tokenize(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var scalars = String.UnicodeScalarView()
        for scalar in folded.lowercased().unicodeScalars {
            scalars.append(CharacterSet.alphanumerics.contains(scalar) ? scalar : " ")
        }
        return String(scalars)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
