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

    private func segment(_ text: String, speaker: String?) -> Segment {
        Segment(
            text: text,
            timestamp: Date(timeIntervalSinceReferenceDate: 0),
            duration: 1,
            speaker: speaker
        )
    }
}
