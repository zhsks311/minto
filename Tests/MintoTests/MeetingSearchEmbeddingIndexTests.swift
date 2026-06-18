import Foundation
import Testing
@testable import MintoCore

@Suite("MeetingSearchEmbeddingIndex")
struct MeetingSearchEmbeddingIndexTests {
    @Test("로컬 embedding provider는 결정론적 vector와 sourceID를 반환한다")
    func localEmbeddingProviderIsDeterministic() async throws {
        let provider = LocalHashEmbeddingProvider(dimensions: 32)

        let first = try await provider.generateEmbedding(LLMEmbeddingRequest(input: "db schema migration", sourceID: "chunk-1"))
        let second = try await provider.generateEmbedding(LLMEmbeddingRequest(input: "db schema migration", sourceID: "chunk-1"))

        #expect(first.providerID == .local)
        #expect(first.modelID == LocalHashEmbeddingProvider.modelID)
        #expect(first.sourceID == "chunk-1")
        #expect(first.kind == .lexicalHash)
        #expect(first.vector.count == 32)
        #expect(first.vector == second.vector)
    }

    @Test("registry는 로컬 embedding provider를 제공한다")
    func registryProvidesLocalEmbeddingProvider() async throws {
        let provider = try #require(LLMProviderRegistry.shared.embeddingProvider(for: .local))
        let catalog = await provider.modelCatalog()

        #expect(provider.descriptor.id == .local)
        #expect(catalog.models.contains { $0.capabilities.contains(.embedding) })
        #expect(LLMProviderRegistry.shared.embeddingProvider(for: .gpt) == nil)
    }

    @Test("embedding builder는 검색 chunk마다 vector record를 만든다")
    func builderEmbedsSearchChunks() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = MeetingRecord(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            title: "db 스키마 회의",
            startedAt: startedAt,
            durationSeconds: 30,
            summary: MeetingSummary(leadAnswer: "liquibase와 flyway를 비교했다."),
            document: "첨부 자료에는 migration playbook이 포함되어 있다.",
            transcript: [
                Segment(
                    id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                    text: "마이그레이션 기록을 검색에 활용한다.",
                    timestamp: startedAt,
                    duration: 3
                )
            ]
        )
        let searchIndex = MeetingSearchIndex(records: [record])
        let builder = MeetingSearchEmbeddingBuilder(provider: LocalHashEmbeddingProvider(dimensions: 16))

        let embeddingIndex = try await builder.build(from: searchIndex)

        #expect(embeddingIndex.providerID == .local)
        #expect(embeddingIndex.modelID == LocalHashEmbeddingProvider.modelID)
        #expect(embeddingIndex.embeddingKind == .lexicalHash)
        #expect(embeddingIndex.dimensions == 16)
        #expect(embeddingIndex.isConsistent)
        #expect(searchIndex.chunks.contains { $0.kind == .document })
        #expect(embeddingIndex.records.count == searchIndex.chunks.count)
        #expect(embeddingIndex.records.allSatisfy { $0.meetingID == record.id })
    }

    @Test("cosine similarity는 같은 vector에 대해 1에 가깝다")
    func cosineSimilarity() {
        let vector = LocalHashEmbeddingProvider.vector(for: "db schema", dimensions: 16)

        let similarity = MeetingSearchEmbeddingIndex.cosineSimilarity(vector, vector)

        #expect(similarity > 0.999)
    }

    @Test("빈 입력 vector는 NaN 없이 zero vector가 된다")
    func emptyInputVectorIsFiniteZeroVector() {
        let vector = LocalHashEmbeddingProvider.vector(for: "   !!!", dimensions: 16)

        #expect(vector.count == 16)
        #expect(vector.allSatisfy { $0 == 0 && $0.isFinite })
        #expect(MeetingSearchEmbeddingIndex.cosineSimilarity(vector, vector) == 0)
    }

    @Test("dimension이 맞지 않으면 similarity를 계산하지 않는다")
    func similarityRejectsDimensionMismatch() {
        let record = MeetingSearchEmbeddingRecord(
            chunkID: "chunk",
            meetingID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            providerID: .local,
            modelID: LocalHashEmbeddingProvider.modelID,
            embeddingKind: .lexicalHash,
            vector: [1, 0]
        )
        let index = MeetingSearchEmbeddingIndex(
            providerID: .local,
            modelID: LocalHashEmbeddingProvider.modelID,
            embeddingKind: .lexicalHash,
            dimensions: 3,
            records: [record]
        )

        #expect(index.isConsistent == false)
        #expect(index.similarity(queryVector: [1, 0, 0], chunkID: "chunk") == nil)
    }
}
