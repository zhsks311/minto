import Testing
@testable import MintoCore
import Foundation

@Suite("VoiceprintMatching")
struct VoiceprintMatchingTests {

    @Test("동일 벡터 코사인은 1이다")
    func cosineSimilarityReturnsOneForSameVector() {
        let similarity = VoiceprintMatching.cosineSimilarity([1, 2, 3], [1, 2, 3])

        #expect(abs(similarity - 1) < 0.000_000_1)
    }

    @Test("직교 벡터 코사인은 0이다")
    func cosineSimilarityReturnsZeroForOrthogonalVectors() {
        #expect(VoiceprintMatching.cosineSimilarity([1, 0], [0, 1]) == 0)
    }

    @Test("차원 불일치 코사인은 0으로 처리한다")
    func cosineSimilarityReturnsZeroForDimensionMismatch() {
        #expect(VoiceprintMatching.cosineSimilarity([1, 0], [1, 0, 0]) == 0)
    }

    @Test("threshold 이상이면 최적 보이스프린트를 반환한다")
    func bestMatchReturnsPrintAboveThreshold() {
        let voiceprint = makeVoiceprint(name: "Alice", embedding: [1, 0], modelID: "speaker-v1")

        let match = VoiceprintMatching.bestMatch(
            for: [1, 0],
            among: [voiceprint],
            embeddingModelID: "speaker-v1",
            threshold: 0.99
        )

        #expect(match?.id == voiceprint.id)
    }

    @Test("threshold 미만이면 nil을 반환한다")
    func bestMatchReturnsNilBelowThreshold() {
        let voiceprint = makeVoiceprint(name: "Alice", embedding: [0, 1], modelID: "speaker-v1")

        let match = VoiceprintMatching.bestMatch(
            for: [1, 0],
            among: [voiceprint],
            embeddingModelID: "speaker-v1",
            threshold: 0.1
        )

        #expect(match == nil)
    }

    @Test("모델ID 불일치 후보는 제외한다")
    func bestMatchExcludesModelMismatch() {
        let voiceprint = makeVoiceprint(name: "Alice", embedding: [1, 0], modelID: "speaker-v2")

        let match = VoiceprintMatching.bestMatch(
            for: [1, 0],
            among: [voiceprint],
            embeddingModelID: "speaker-v1",
            threshold: 0
        )

        #expect(match == nil)
    }

    @Test("차원 불일치 후보는 제외한다")
    func bestMatchExcludesDimensionMismatch() {
        let voiceprint = makeVoiceprint(name: "Alice", embedding: [1, 0, 0], modelID: "speaker-v1")

        let match = VoiceprintMatching.bestMatch(
            for: [1, 0],
            among: [voiceprint],
            embeddingModelID: "speaker-v1",
            threshold: 0
        )

        #expect(match == nil)
    }

    @Test("후보 여럿 중 코사인 최댓값을 선택한다")
    func bestMatchReturnsHighestScoringPrint() {
        let lower = makeVoiceprint(name: "Lower", embedding: [1, 1], modelID: "speaker-v1")
        let higher = makeVoiceprint(name: "Higher", embedding: [1, 0], modelID: "speaker-v1")

        let match = VoiceprintMatching.bestMatch(
            for: [1, 0],
            among: [lower, higher],
            embeddingModelID: "speaker-v1",
            threshold: 0
        )

        #expect(match?.id == higher.id)
    }

    private func makeVoiceprint(name: String, embedding: [Float], modelID: String) -> Voiceprint {
        Voiceprint(
            displayName: name,
            embedding: embedding,
            embeddingModelID: modelID,
            enrolledAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

@MainActor
@Suite("VoiceprintStore", .serialized)
struct VoiceprintStoreTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-voiceprints-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("add 후 새 store에서 다시 읽는다")
    func addAndLoadRoundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = VoiceprintStore(directory: dir)
        #expect(store.add(name: "Alice", embedding: [1, 0, 0], embeddingModelID: "speaker-v1"))

        let added = try #require(store.voiceprints.first)
        let reloaded = VoiceprintStore(directory: dir)
        let loaded = try #require(reloaded.voiceprints.first)

        #expect(reloaded.voiceprints.count == 1)
        #expect(loaded.id == added.id)
        #expect(loaded.displayName == "Alice")
        #expect(loaded.embedding == [1, 0, 0])
        #expect(loaded.embeddingModelID == "speaker-v1")
        #expect(loaded.dimensions == 3)
        #expect(loaded.sampleCount == 1)
        #expect(abs(loaded.enrolledAt.timeIntervalSince(added.enrolledAt)) < 1)
    }

    @Test("rename은 이름을 바꾸고 저장한다")
    func renameUpdatesStoredVoiceprint() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = VoiceprintStore(directory: dir)
        #expect(store.add(name: "Alice", embedding: [1, 0], embeddingModelID: "speaker-v1"))
        let id = try #require(store.voiceprints.first?.id)

        #expect(store.rename(id: id, to: "Bob"))

        let reloaded = VoiceprintStore(directory: dir)
        #expect(reloaded.voiceprints.first?.displayName == "Bob")
    }

    @Test("delete는 보이스프린트를 제거하고 저장한다")
    func deleteRemovesStoredVoiceprint() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = VoiceprintStore(directory: dir)
        #expect(store.add(name: "Alice", embedding: [1, 0], embeddingModelID: "speaker-v1"))
        let id = try #require(store.voiceprints.first?.id)

        #expect(store.delete(id: id))
        #expect(store.voiceprints.isEmpty)
        #expect(VoiceprintStore(directory: dir).voiceprints.isEmpty)
    }

    @Test("usablePrints는 현재 모델ID와 맞는 항목만 반환한다")
    func usablePrintsFiltersByModelID() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = VoiceprintStore(directory: dir)
        #expect(store.add(name: "Alice", embedding: [1, 0], embeddingModelID: "speaker-v1"))
        #expect(store.add(name: "Bob", embedding: [0, 1], embeddingModelID: "speaker-v2"))

        let usable = store.usablePrints(forModelID: "speaker-v1")

        #expect(usable.map(\.displayName) == ["Alice"])
    }
}
