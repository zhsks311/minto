import Testing
@testable import MintoCore

@Suite("LiveDiarizationReconciler")
struct LiveDiarizationReconcilerTests {

    private func segment(_ id: String, _ start: Double, _ end: Double) -> DiarizedSpeakerSegment {
        DiarizedSpeakerSegment(speakerId: id, startSeconds: start, endSeconds: end)
    }

    @Test("겹치는 화자쌍을 1:1로 매핑한다")
    func mapsOneToOne() {
        let live = [segment("S1", 0, 10), segment("S2", 10, 20)]
        let final = [segment("A", 0, 10), segment("B", 10, 20)]

        let map = LiveDiarizationReconciler.mapLabels(live: live, final: final)

        #expect(map["S1"] == "A")
        #expect(map["S2"] == "B")
        #expect(map.count == 2)
    }

    @Test("매칭 안 되는 라이브 라벨은 맵에서 제외된다")
    func dropsUnmatchedLiveLabel() {
        // S3는 final 어느 라벨과도 겹치지 않음
        let live = [segment("S1", 0, 10), segment("S2", 10, 20), segment("S3", 20, 21)]
        let final = [segment("A", 0, 10), segment("B", 10, 20)]

        let map = LiveDiarizationReconciler.mapLabels(live: live, final: final)

        #expect(map["S1"] == "A")
        #expect(map["S2"] == "B")
        #expect(map["S3"] == nil)
        #expect(map.count == 2)
    }

    @Test("IOU 동점이면 더 이른 등장 라이브 라벨이 우선 매칭된다")
    func breaksTieByEarlierStart() {
        // S1, S2 모두 A와 겹침 길이 5초로 IOU 동일 → S1(start 0)이 A를 가져가고 S2는 미매칭
        let live = [segment("S1", 0, 5), segment("S2", 10, 15)]
        let final = [segment("A", 0, 20)]

        let map = LiveDiarizationReconciler.mapLabels(live: live, final: final)

        #expect(map["S1"] == "A")
        #expect(map["S2"] == nil)
    }

    @Test("빈 입력은 빈 맵을 반환한다")
    func emptyInputs() {
        #expect(LiveDiarizationReconciler.mapLabels(live: [], final: [segment("A", 0, 10)]).isEmpty)
        #expect(LiveDiarizationReconciler.mapLabels(live: [segment("S1", 0, 10)], final: []).isEmpty)
    }

    @Test("미편집 segment는 맵대로, 편집 segment는 라이브 라벨을 보존한다")
    func resolvePreservesEdits() {
        let transcript: [(liveLabel: String, edited: Bool)] = [
            ("S1", false),  // 맵대로 → A
            ("S2", true),   // 편집됨 → 보존 (S2)
            ("S3", false),  // 맵대로 → B
        ]
        let labelMap = ["S1": "A", "S2": "X", "S3": "B"]

        let resolved = LiveDiarizationReconciler.resolveFinalLabels(transcript: transcript, labelMap: labelMap)

        #expect(resolved == ["A", "S2", "B"])
    }

    @Test("맵에 없는 미편집 라벨은 라이브 라벨로 fallback한다")
    func resolveFallsBackWhenUnmapped() {
        let transcript: [(liveLabel: String, edited: Bool)] = [("S4", false)]
        let resolved = LiveDiarizationReconciler.resolveFinalLabels(transcript: transcript, labelMap: ["S1": "A"])

        #expect(resolved == ["S4"])
    }
}
