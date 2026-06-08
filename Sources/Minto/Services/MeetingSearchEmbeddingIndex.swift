import Foundation

public struct MeetingSearchEmbeddingRecord: Identifiable, Codable, Sendable, Equatable {
    public let chunkID: String
    public let meetingID: UUID
    public let providerID: LLMProviderID
    public let modelID: String
    public let embeddingKind: LLMEmbeddingKind
    public let vector: [Double]

    public var id: String { chunkID }

    public init(
        chunkID: String,
        meetingID: UUID,
        providerID: LLMProviderID,
        modelID: String,
        embeddingKind: LLMEmbeddingKind,
        vector: [Double]
    ) {
        self.chunkID = chunkID
        self.meetingID = meetingID
        self.providerID = providerID
        self.modelID = modelID
        self.embeddingKind = embeddingKind
        self.vector = vector
    }
}

public struct MeetingSearchEmbeddingIndex: Codable, Sendable, Equatable {
    public let providerID: LLMProviderID
    public let modelID: String
    public let embeddingKind: LLMEmbeddingKind
    public let dimensions: Int
    public let records: [MeetingSearchEmbeddingRecord]

    public init(
        providerID: LLMProviderID,
        modelID: String,
        embeddingKind: LLMEmbeddingKind,
        dimensions: Int,
        records: [MeetingSearchEmbeddingRecord]
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.embeddingKind = embeddingKind
        self.dimensions = dimensions
        self.records = records
    }

    public var isConsistent: Bool {
        dimensions > 0 && records.allSatisfy {
            $0.providerID == providerID
                && $0.modelID == modelID
                && $0.embeddingKind == embeddingKind
                && $0.vector.count == dimensions
                && $0.vector.allSatisfy { $0.isFinite }
        }
    }

    public func vector(for chunkID: String) -> [Double]? {
        records.first { $0.chunkID == chunkID }?.vector
    }

    public func similarity(queryVector: [Double], chunkID: String) -> Double? {
        guard queryVector.count == dimensions, let vector = vector(for: chunkID), vector.count == dimensions else {
            return nil
        }
        return Self.cosineSimilarity(queryVector, vector)
    }

    public static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0
        var lhsNorm = 0.0
        var rhsNorm = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }
        guard lhsNorm > 0, rhsNorm > 0 else { return 0 }
        return dot / (sqrt(lhsNorm) * sqrt(rhsNorm))
    }
}

public actor MeetingSearchEmbeddingBuilder {
    private let provider: any LLMEmbeddingProvider

    public init(provider: any LLMEmbeddingProvider) {
        self.provider = provider
    }

    public func build(from index: MeetingSearchIndex, modelID: String? = nil) async throws -> MeetingSearchEmbeddingIndex {
        var records: [MeetingSearchEmbeddingRecord] = []
        records.reserveCapacity(index.chunks.count)

        for chunk in index.chunks {
            let response = try await provider.generateEmbedding(
                LLMEmbeddingRequest(input: chunk.text, modelID: modelID, sourceID: chunk.id)
            )
            records.append(
                MeetingSearchEmbeddingRecord(
                    chunkID: chunk.id,
                    meetingID: chunk.meetingID,
                    providerID: response.providerID,
                    modelID: response.modelID,
                    embeddingKind: response.kind,
                    vector: response.vector
                )
            )
        }

        let first = records.first
        return MeetingSearchEmbeddingIndex(
            providerID: first?.providerID ?? provider.descriptor.id,
            modelID: first?.modelID ?? modelID ?? "",
            embeddingKind: first?.embeddingKind ?? .semantic,
            dimensions: first?.vector.count ?? 0,
            records: records
        )
    }
}
