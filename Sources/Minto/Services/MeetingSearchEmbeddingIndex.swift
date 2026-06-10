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

    /// 토큰 기반 검색 결과를 임베딩 코사인 유사도로 재랭킹한다.
    ///
    /// - Parameters:
    ///   - results: 원 검색 결과 (토큰 점수 기준 정렬)
    ///   - queryVector: 쿼리 임베딩 벡터
    ///   - embeddings: 청크 임베딩 인덱스
    ///   - weight: 코사인 기여 비중 (0~1). 0이면 원순위 반환
    /// - Returns: 혼합 점수 `(1-weight)*정규화토큰점수 + weight*코사인` 기준 정렬 결과.
    ///   차원 불일치·벡터 없음·정규화 불가 등 어떤 문제든 원순위 그대로 반환(fail-soft).
    public static func rerank(
        results: [MeetingSearchResult],
        queryVector: [Double],
        embeddings: MeetingSearchEmbeddingIndex,
        weight: Double = 0.25
    ) -> [MeetingSearchResult] {
        guard !results.isEmpty, weight > 0 else { return results }

        let maxScore = results.map(\.score).max() ?? 0
        guard maxScore > 0 else { return results }

        let reranked = results.map { result -> (result: MeetingSearchResult, mixedScore: Double) in
            let normalizedTokenScore = result.score / maxScore
            let cosine = embeddings.similarity(queryVector: queryVector, chunkID: result.chunk.id) ?? normalizedTokenScore
            let mixedScore = (1 - weight) * normalizedTokenScore + weight * cosine
            return (result: result, mixedScore: mixedScore)
        }

        return reranked
            .sorted { $0.mixedScore > $1.mixedScore }
            .map(\.result)
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
