import Foundation
import Testing
@testable import MintoCore

@Suite("MeetingSearchRerank")
struct MeetingSearchRerankTests {

    // MARK: - 헬퍼

    private func makeResult(chunkID: String, score: Double) -> MeetingSearchResult {
        let meetingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let chunk = MeetingSearchChunk(
            id: chunkID,
            meetingID: meetingID,
            meetingTitle: "테스트 회의",
            meetingStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .summary,
            text: chunkID,
            sourcePath: chunkID,
            checksum: chunkID,
            chunkingVersion: 1,
            order: 0
        )
        return MeetingSearchResult(chunk: chunk, score: score, matchedTerms: [], preview: "")
    }

    private func makeEmbeddingIndex(
        chunkIDs: [String],
        vectors: [[Double]]
    ) -> MeetingSearchEmbeddingIndex {
        let records = zip(chunkIDs, vectors).map { chunkID, vector in
            MeetingSearchEmbeddingRecord(
                chunkID: chunkID,
                meetingID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                providerID: .local,
                modelID: LocalHashEmbeddingProvider.modelID,
                embeddingKind: .lexicalHash,
                vector: vector
            )
        }
        return MeetingSearchEmbeddingIndex(
            providerID: .local,
            modelID: LocalHashEmbeddingProvider.modelID,
            embeddingKind: .lexicalHash,
            dimensions: vectors.first?.count ?? 0,
            records: records
        )
    }

    // MARK: - 코사인 우위로 순위 역전

    @Test("코사인 유사도 우위로 하위 토큰 점수 결과가 상위로 역전된다")
    func rerankInvertsOrderWhenCosineDominates() {
        // chunk-high: 토큰 점수 높음, 코사인 낮음
        // chunk-low: 토큰 점수 낮음, 코사인 높음 (쿼리 벡터와 동일)
        let resultHigh = makeResult(chunkID: "chunk-high", score: 20.0)
        let resultLow = makeResult(chunkID: "chunk-low", score: 5.0)

        let queryVector = [1.0, 0.0, 0.0]
        // chunk-high: 쿼리와 직교 → 코사인 0
        // chunk-low: 쿼리와 동일 → 코사인 ≈ 1
        let embeddingIndex = makeEmbeddingIndex(
            chunkIDs: ["chunk-high", "chunk-low"],
            vectors: [[0.0, 1.0, 0.0], [1.0, 0.0, 0.0]]
        )

        let reranked = MeetingSearchEmbeddingIndex.rerank(
            results: [resultHigh, resultLow],
            queryVector: queryVector,
            embeddings: embeddingIndex,
            weight: 0.9  // 코사인 비중 매우 높게
        )

        #expect(reranked.first?.id == "chunk-low", "코사인 우위인 chunk-low가 1위가 되어야 함")
        #expect(reranked.last?.id == "chunk-high")
    }

    // MARK: - weight 0이면 원순위 유지

    @Test("weight가 0이면 원순위를 그대로 반환한다")
    func weightZeroPreservesOriginalOrder() {
        let results = [
            makeResult(chunkID: "first", score: 20.0),
            makeResult(chunkID: "second", score: 10.0),
            makeResult(chunkID: "third", score: 5.0)
        ]
        let queryVector = [1.0, 0.0]
        let embeddingIndex = makeEmbeddingIndex(
            chunkIDs: ["first", "second", "third"],
            vectors: [[0.0, 1.0], [0.0, 1.0], [1.0, 0.0]]  // third가 코사인 1이지만
        )

        let reranked = MeetingSearchEmbeddingIndex.rerank(
            results: results,
            queryVector: queryVector,
            embeddings: embeddingIndex,
            weight: 0
        )

        #expect(reranked.map(\.id) == ["first", "second", "third"])
    }

    // MARK: - 차원 불일치 시 원순위 유지

    @Test("쿼리 벡터와 임베딩 차원이 다르면 원순위를 반환한다")
    func dimensionMismatchPreservesOriginalOrder() {
        let results = [
            makeResult(chunkID: "a", score: 5.0),
            makeResult(chunkID: "b", score: 20.0)
        ]
        // embeddings.dimensions = 3이지만 queryVector = 2차원 → similarity = nil
        let queryVector = [1.0, 0.0]  // 2차원
        let embeddingIndex = makeEmbeddingIndex(
            chunkIDs: ["a", "b"],
            vectors: [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]  // 3차원
        )

        let reranked = MeetingSearchEmbeddingIndex.rerank(
            results: results,
            queryVector: queryVector,
            embeddings: embeddingIndex,
            weight: 0.5
        )

        // similarity가 nil이므로 normalizedTokenScore를 코사인 대신 사용 →
        // b(점수 20)가 여전히 1위, a(점수 5)가 2위
        #expect(reranked.first?.id == "b")
        #expect(reranked.last?.id == "a")
    }

    // MARK: - 빈 결과 처리

    @Test("결과가 비었으면 빈 배열을 반환한다")
    func emptyResultsReturnsEmpty() {
        let embeddingIndex = makeEmbeddingIndex(chunkIDs: [], vectors: [])
        let reranked = MeetingSearchEmbeddingIndex.rerank(
            results: [],
            queryVector: [1.0, 0.0],
            embeddings: embeddingIndex
        )
        #expect(reranked.isEmpty)
    }

    // MARK: - 벡터 없는 청크는 정규화 점수로 대체

    @Test("임베딩 인덱스에 없는 청크는 정규화된 토큰 점수를 코사인 대신 사용한다")
    func missingChunkVectorFallsBackToNormalizedScore() {
        let results = [
            makeResult(chunkID: "known", score: 10.0),
            makeResult(chunkID: "unknown", score: 10.0)  // 동점
        ]
        let queryVector = [1.0, 0.0]
        // "known"만 인덱스에 있고, 코사인 = 0
        let embeddingIndex = makeEmbeddingIndex(
            chunkIDs: ["known"],
            vectors: [[0.0, 1.0]]
        )

        let reranked = MeetingSearchEmbeddingIndex.rerank(
            results: results,
            queryVector: queryVector,
            embeddings: embeddingIndex,
            weight: 0.25
        )

        // 두 결과 모두 반환되어야 함
        #expect(reranked.count == 2)
    }
}
