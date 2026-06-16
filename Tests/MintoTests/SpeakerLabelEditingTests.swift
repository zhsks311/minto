import Foundation
import Testing
@testable import MintoCore

@Suite("SpeakerLabelEditing")
struct SpeakerLabelEditingTests {
    @Test("labels: 빈 segment 배열은 빈 결과를 반환한다")
    func labelsReturnsEmptyForEmptySegments() {
        #expect(SpeakerLabelEditing.labels(in: []) == [])
    }

    @Test("labels: nil과 빈 speaker를 제외하고 중복 라벨은 첫 등장 순서만 남긴다")
    func labelsNormalizeDeduplicateAndPreserveFirstAppearanceOrder() {
        let segments = [
            segment("nil speaker", speaker: nil),
            segment("first", speaker: " 화자 1 "),
            segment("blank", speaker: " "),
            segment("second", speaker: "화자 2"),
            segment("duplicate", speaker: "화자 1"),
            segment("third", speaker: "\n화자 3\t"),
        ]

        #expect(SpeakerLabelEditing.labels(in: segments) == ["화자 1", "화자 2", "화자 3"])
    }

    @Test("replacingSpeaker: source speaker 전체를 target으로 치환한다")
    func replacingSpeakerUpdatesEveryMatchingSegment() {
        let segments = [
            segment("a", speaker: "화자 1"),
            segment("b", speaker: "화자 2"),
            segment("c", speaker: "화자 1"),
            segment("d", speaker: nil),
        ]

        let updated = SpeakerLabelEditing.replacingSpeaker("화자 1", with: "PM", in: segments)

        #expect(updated.map(\.speaker) == ["PM", "화자 2", "PM", nil])
        #expect(updated.map(\.id) == segments.map(\.id))
    }

    @Test("replacingSpeaker: 매칭 없는 source는 원본을 유지한다")
    func replacingSpeakerKeepsSegmentsWhenSourceDoesNotMatch() {
        let segments = [
            segment("a", speaker: "화자 1"),
            segment("b", speaker: nil),
        ]

        let updated = SpeakerLabelEditing.replacingSpeaker("화자 3", with: "PM", in: segments)

        #expect(updated == segments)
    }

    @Test("replacingSpeaker: source와 target 라벨 공백은 정규화해서 비교하고 저장한다")
    func replacingSpeakerNormalizesSourceAndTargetWhitespace() {
        let segments = [
            segment("a", speaker: " 화자 1\n"),
            segment("b", speaker: "화자 1"),
            segment("c", speaker: "화자 2"),
        ]

        let updated = SpeakerLabelEditing.replacingSpeaker("  화자 1 ", with: "\tPM\n", in: segments)

        #expect(updated.map(\.speaker) == ["PM", "PM", "화자 2"])
    }

    @Test("replacingSpeaker: source와 target이 같으면 원본을 유지한다")
    func replacingSpeakerKeepsSegmentsWhenSourceAndTargetAreSame() {
        let segments = [
            segment("a", speaker: " 화자 1 "),
            segment("b", speaker: "화자 2"),
        ]

        let updated = SpeakerLabelEditing.replacingSpeaker("화자 1", with: " 화자 1 ", in: segments)

        #expect(updated == segments)
    }

    @Test("reassignSegment: 지정 구간 하나만 target speaker로 변경한다")
    func reassignSegmentUpdatesOnlyMatchingSegment() {
        let targetID = Segment.ID()
        let segments = [
            segment("a", speaker: "화자 1"),
            segment("b", speaker: "화자 2", id: targetID),
            segment("c", speaker: "화자 3"),
        ]

        let updated = SpeakerLabelEditing.reassignSegment(id: targetID, to: "PM", in: segments)

        #expect(updated.map(\.speaker) == ["화자 1", "PM", "화자 3"])
        #expect(updated[0] == segments[0])
        #expect(updated[2] == segments[2])
    }

    @Test("reassignSegment: 없는 id는 원본을 유지한다")
    func reassignSegmentKeepsSegmentsWhenIDDoesNotMatch() {
        let segments = [
            segment("a", speaker: "화자 1"),
            segment("b", speaker: "화자 2"),
        ]

        let updated = SpeakerLabelEditing.reassignSegment(id: Segment.ID(), to: "PM", in: segments)

        #expect(updated == segments)
    }

    @Test("reassignSegment: 빈 target 라벨은 원본을 유지한다")
    func reassignSegmentKeepsSegmentsWhenTargetLabelIsBlank() {
        let targetID = Segment.ID()
        let segments = [
            segment("a", speaker: "화자 1", id: targetID),
            segment("b", speaker: "화자 2"),
        ]

        let updated = SpeakerLabelEditing.reassignSegment(id: targetID, to: " \n\t", in: segments)

        #expect(updated == segments)
    }

    @Test("reassignSegment: target 라벨 공백을 정규화해서 저장한다")
    func reassignSegmentNormalizesTargetWhitespace() {
        let targetID = Segment.ID()
        let segments = [
            segment("a", speaker: "화자 1", id: targetID),
            segment("b", speaker: "화자 2"),
        ]

        let updated = SpeakerLabelEditing.reassignSegment(id: targetID, to: "\tPM\n", in: segments)

        #expect(updated.map(\.speaker) == ["PM", "화자 2"])
    }

    @Test("nextNewSpeakerLabel: 기존 라벨이 없으면 화자 1을 반환한다")
    func nextNewSpeakerLabelReturnsFirstSpeakerForEmptyLabels() {
        #expect(SpeakerLabelEditing.nextNewSpeakerLabel(existing: []) == "화자 1")
    }

    @Test("nextNewSpeakerLabel: 사용 중인 화자 번호 다음 최소 번호를 반환한다")
    func nextNewSpeakerLabelReturnsSmallestUnusedSpeakerNumber() {
        #expect(SpeakerLabelEditing.nextNewSpeakerLabel(existing: ["화자 1"]) == "화자 2")
        #expect(SpeakerLabelEditing.nextNewSpeakerLabel(existing: ["화자 1", "화자 3"]) == "화자 2")
    }

    @Test("nextNewSpeakerLabel: 임의 라벨과 겹치지 않는 화자 라벨을 반환한다")
    func nextNewSpeakerLabelAvoidsCollisionWithArbitraryLabels() {
        #expect(SpeakerLabelEditing.nextNewSpeakerLabel(existing: ["A", "화자 1", "화자 2"]) == "화자 3")
    }

    private func segment(_ text: String, speaker: String?, id: Segment.ID = Segment.ID()) -> Segment {
        Segment(
            id: id,
            text: text,
            timestamp: Date(timeIntervalSinceReferenceDate: 0),
            duration: 1,
            speaker: speaker
        )
    }
}
