import Foundation
import Testing
@testable import MintoCore

/// 쿼리 확장 + LocalHash 재랭킹 통합 테스트.
///
/// 단위 테스트(GlossaryQueryExpanderTests, MeetingSearchRerankTests)와 달리
/// 실제 검색 파이프라인 전체를 통해 두 기능이 함께 동작하는지 검증한다.
@Suite("SearchEmbeddingIntegration")
struct SearchEmbeddingIntegrationTests {

    // MARK: - 헬퍼

    private static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecord(
        id: String,
        title: String,
        leadAnswer: String,
        startOffset: TimeInterval = 0
    ) -> MeetingRecord {
        MeetingRecord(
            id: UUID(uuidString: id)!,
            title: title,
            startedAt: Self.baseDate.addingTimeInterval(startOffset),
            durationSeconds: 60,
            summary: MeetingSummary(leadAnswer: leadAnswer)
        )
    }

    // MARK: - 1. 쿼리 확장

    @Test("확장 쿼리: '리퀴베이스' 검색 시 Liquibase만 포함한 회의가 결과에 포함된다")
    func expandedQueryFindsCanonicalOnlyMeeting() {
        let canonicalOnlyRecord = makeRecord(
            id: "11111111-1111-1111-1111-111111111111",
            title: "DB 마이그레이션",
            leadAnswer: "Liquibase로 스키마를 관리한다."
        )
        let index = MeetingSearchIndex(records: [canonicalOnlyRecord])
        let entries = [GlossaryEntry(canonical: "Liquibase", aliases: ["리퀴베이스"])]

        let queryTokens = MeetingSearchIndex.queryTerms("리퀴베이스")
        let expandedTokens = GlossaryQueryExpander.expand(
            queryTokens: queryTokens,
            entries: entries.filter(\.isUsable)
        )

        // 확장 없으면 결과 없음
        let withoutExpansion = index.search("리퀴베이스", limit: .max)
        #expect(withoutExpansion.isEmpty)

        // 확장 있으면 결과 포함
        let withExpansion = index.search("리퀴베이스", limit: .max, expandedTokens: expandedTokens)
        #expect(!withExpansion.isEmpty)
        #expect(withExpansion.allSatisfy { $0.meetingID == canonicalOnlyRecord.id })
    }

    // MARK: - 2. 코사인 우위로 순위 역전

    @Test("코사인 우위: 임베딩 유사도가 높은 청크가 토큰 점수 낮아도 재랭킹 후 상위에 온다")
    func rerankElevatesCosineSuperiorChunk() {
        // chunk-high: 토큰 점수 높음, 쿼리와 직교 → 코사인 ≈ 0
        // chunk-low:  토큰 점수 낮음, 쿼리와 동일 → 코사인 ≈ 1
        let meetingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let makeChunk = { (id: String) in
            MeetingSearchChunk(
                id: id,
                meetingID: meetingID,
                meetingTitle: "테스트 회의",
                meetingStartedAt: Self.baseDate,
                kind: .summary,
                text: id,
                sourcePath: id,
                checksum: id,
                chunkingVersion: 1,
                order: 0
            )
        }
        let resultHigh = MeetingSearchResult(chunk: makeChunk("chunk-high"), score: 30.0, matchedTerms: [], preview: "")
        let resultLow  = MeetingSearchResult(chunk: makeChunk("chunk-low"),  score:  5.0, matchedTerms: [], preview: "")

        let queryVector = [1.0, 0.0, 0.0]
        let records = [
            MeetingSearchEmbeddingRecord(
                chunkID: "chunk-high",
                meetingID: meetingID,
                providerID: .local,
                modelID: LocalHashEmbeddingProvider.modelID,
                embeddingKind: .lexicalHash,
                vector: [0.0, 1.0, 0.0]   // 직교 → 코사인 0
            ),
            MeetingSearchEmbeddingRecord(
                chunkID: "chunk-low",
                meetingID: meetingID,
                providerID: .local,
                modelID: LocalHashEmbeddingProvider.modelID,
                embeddingKind: .lexicalHash,
                vector: [1.0, 0.0, 0.0]   // 동일 → 코사인 1
            )
        ]
        let embeddingIndex = MeetingSearchEmbeddingIndex(
            providerID: .local,
            modelID: LocalHashEmbeddingProvider.modelID,
            embeddingKind: .lexicalHash,
            dimensions: 3,
            records: records
        )

        let reranked = MeetingSearchEmbeddingIndex.rerank(
            results: [resultHigh, resultLow],
            queryVector: queryVector,
            embeddings: embeddingIndex,
            weight: 0.9   // 코사인 비중 매우 높게
        )

        #expect(reranked.first?.id == "chunk-low", "코사인 우위인 chunk-low가 재랭킹 후 1위여야 함")
        #expect(reranked.last?.id == "chunk-high")
    }

    // MARK: - 3. 빌드 통합: LocalHash 임베딩 빌더가 인덱스를 생성한다

    @Test("빌드 통합: MeetingSearchEmbeddingBuilder가 검색 인덱스에서 임베딩 인덱스를 빌드한다")
    func builderProducesEmbeddingIndex() async throws {
        let record = makeRecord(
            id: "22222222-2222-2222-2222-222222222222",
            title: "빌드 테스트 회의",
            leadAnswer: "LocalHash 임베딩을 사용해 재랭킹한다."
        )
        let searchIndex = MeetingSearchIndex(records: [record])
        let builder = MeetingSearchEmbeddingBuilder(provider: LocalHashEmbeddingProvider(dimensions: 32))

        let embeddingIndex = try await builder.build(from: searchIndex)

        #expect(embeddingIndex.providerID == .local)
        #expect(embeddingIndex.dimensions == 32)
        #expect(embeddingIndex.isConsistent)
        #expect(embeddingIndex.records.count == searchIndex.chunks.count)
        #expect(embeddingIndex.records.count > 0)
    }

    // MARK: - 4. fail-soft: 차원 불일치 시 원순위 유지

    @Test("fail-soft: 쿼리 벡터와 임베딩 차원 불일치 시 원순위를 그대로 반환한다")
    func dimensionMismatchPreservesOriginalOrder() {
        let meetingID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let makeResult = { (id: String, score: Double) in
            MeetingSearchResult(
                chunk: MeetingSearchChunk(
                    id: id,
                    meetingID: meetingID,
                    meetingTitle: "테스트",
                    meetingStartedAt: Self.baseDate,
                    kind: .summary,
                    text: id,
                    sourcePath: id,
                    checksum: id,
                    chunkingVersion: 1,
                    order: 0
                ),
                score: score,
                matchedTerms: [],
                preview: ""
            )
        }
        let results = [
            makeResult("first",  20.0),
            makeResult("second", 10.0),
            makeResult("third",   5.0)
        ]
        // 3차원 임베딩 vs 2차원 쿼리 → similarity = nil → fail-soft
        let records = results.map { result in
            MeetingSearchEmbeddingRecord(
                chunkID: result.id,
                meetingID: meetingID,
                providerID: .local,
                modelID: LocalHashEmbeddingProvider.modelID,
                embeddingKind: .lexicalHash,
                vector: [1.0, 0.0, 0.0]   // 3차원
            )
        }
        let embeddingIndex = MeetingSearchEmbeddingIndex(
            providerID: .local,
            modelID: LocalHashEmbeddingProvider.modelID,
            embeddingKind: .lexicalHash,
            dimensions: 3,
            records: records
        )

        let reranked = MeetingSearchEmbeddingIndex.rerank(
            results: results,
            queryVector: [1.0, 0.0],   // 2차원 — 차원 불일치
            embeddings: embeddingIndex,
            weight: 0.25
        )

        // similarity가 nil이므로 정규화 토큰 점수를 대체 사용 → 원래 순서 유지
        #expect(reranked.map(\.id) == ["first", "second", "third"])
    }
}
