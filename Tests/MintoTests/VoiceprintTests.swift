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

    @Test("화자별 centroid는 평균 후 정규화한다")
    func centroidsAverageEmbeddingsBySpeaker() throws {
        let centroids = VoiceprintMatching.centroids(
            from: [
                (speakerId: "speaker-b", embedding: [1, 0]),
                (speakerId: "speaker-a", embedding: [2, 0]),
                (speakerId: "speaker-a", embedding: [0, 2])
            ]
        )

        let speakerA = try #require(centroids.first { $0.speakerId == "speaker-a" })
        #expect(abs(Double(speakerA.centroid[0]) - sqrt(0.5)) < 0.000_000_1)
        #expect(abs(Double(speakerA.centroid[1]) - sqrt(0.5)) < 0.000_000_1)
    }

    @Test("빈 입력 centroid는 빈 결과를 반환한다")
    func centroidsReturnEmptyForEmptyInput() {
        #expect(VoiceprintMatching.centroids(from: []).isEmpty)
    }

    @Test("한 화자의 여러 임베딩은 centroid 하나로 합친다")
    func centroidsReturnOneCentroidPerSpeaker() {
        let centroids = VoiceprintMatching.centroids(
            from: [
                (speakerId: "speaker-a", embedding: [1, 0]),
                (speakerId: "speaker-a", embedding: [0, 1]),
                (speakerId: "speaker-a", embedding: [1, 1])
            ]
        )

        #expect(centroids.count == 1)
        #expect(centroids.first?.speakerId == "speaker-a")
    }

    @Test("centroid는 L2 정규화한다")
    func centroidsNormalizeToUnitLength() throws {
        let centroid = try #require(
            VoiceprintMatching.centroids(
                from: [
                    (speakerId: "speaker-a", embedding: [3, 0]),
                    (speakerId: "speaker-a", embedding: [0, 4])
                ]
            ).first?.centroid
        )

        let norm = sqrt(centroid.reduce(0.0) { $0 + (Double($1) * Double($1)) })
        #expect(abs(norm - 1) < 0.000_000_1)
    }

    @Test("차원이 섞인 화자는 centroid에서 제외한다")
    func centroidsExcludeSpeakerWithMixedDimensions() {
        let centroids = VoiceprintMatching.centroids(
            from: [
                (speakerId: "speaker-a", embedding: [1, 0]),
                (speakerId: "speaker-a", embedding: [1, 0, 0]),
                (speakerId: "speaker-b", embedding: [0, 1])
            ]
        )

        #expect(centroids.map { $0.speakerId } == ["speaker-b"])
    }

    @Test("centroid 반환 순서는 speakerId 정렬을 따른다")
    func centroidsSortBySpeakerID() {
        let centroids = VoiceprintMatching.centroids(
            from: [
                (speakerId: "speaker-c", embedding: [0, 1]),
                (speakerId: "speaker-a", embedding: [1, 0]),
                (speakerId: "speaker-b", embedding: [1, 1])
            ]
        )

        #expect(centroids.map { $0.speakerId } == ["speaker-a", "speaker-b", "speaker-c"])
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

    @Test("identifySpeakers는 threshold 이상 단일 라벨을 매칭한다")
    func identifySpeakersMatchesSingleLabelAboveThreshold() throws {
        let voiceprint = makeVoiceprint(name: "Alice", embedding: [1, 0], modelID: "speaker-v1")

        let result = VoiceprintMatching.identifySpeakers(
            labeledCentroids: [(speakerLabel: "화자 1", centroid: [1, 0])],
            among: [voiceprint],
            embeddingModelID: "speaker-v1",
            threshold: 0.99
        )

        let matched = try #require(result["화자 1"])
        #expect(matched.id == voiceprint.id)
    }

    @Test("identifySpeakers는 threshold 미만이면 빈 맵을 반환한다")
    func identifySpeakersReturnsEmptyBelowThreshold() {
        let voiceprint = makeVoiceprint(name: "Alice", embedding: [0, 1], modelID: "speaker-v1")

        let result = VoiceprintMatching.identifySpeakers(
            labeledCentroids: [(speakerLabel: "화자 1", centroid: [1, 0])],
            among: [voiceprint],
            embeddingModelID: "speaker-v1",
            threshold: 0.1
        )

        #expect(result.isEmpty)
    }

    @Test("identifySpeakers는 모델ID 불일치 후보를 제외한다")
    func identifySpeakersExcludesModelMismatch() {
        let voiceprint = makeVoiceprint(name: "Alice", embedding: [1, 0], modelID: "speaker-v2")

        let result = VoiceprintMatching.identifySpeakers(
            labeledCentroids: [(speakerLabel: "화자 1", centroid: [1, 0])],
            among: [voiceprint],
            embeddingModelID: "speaker-v1",
            threshold: 0
        )

        #expect(result.isEmpty)
    }

    @Test("identifySpeakers는 같은 보이스프린트를 두 라벨에 중복 배정하지 않는다")
    func identifySpeakersAssignsOnePrintToHighestScoringLabel() throws {
        let voiceprint = makeVoiceprint(name: "Alice", embedding: [1, 0], modelID: "speaker-v1")

        let result = VoiceprintMatching.identifySpeakers(
            labeledCentroids: [
                (speakerLabel: "화자 1", centroid: [1, 0]),
                (speakerLabel: "화자 2", centroid: [0.8, 0.6])
            ],
            among: [voiceprint],
            embeddingModelID: "speaker-v1",
            threshold: 0.1
        )

        let matched = try #require(result["화자 1"])
        #expect(matched.id == voiceprint.id)
        #expect(result["화자 2"] == nil)
    }

    @Test("identifySpeakers는 빈 입력이면 빈 맵을 반환한다")
    func identifySpeakersReturnsEmptyForEmptyInput() {
        let voiceprint = makeVoiceprint(name: "Alice", embedding: [1, 0], modelID: "speaker-v1")

        let result = VoiceprintMatching.identifySpeakers(
            labeledCentroids: [],
            among: [voiceprint],
            embeddingModelID: "speaker-v1",
            threshold: 0
        )

        #expect(result.isEmpty)
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
