import Foundation
import Testing
@testable import MintoCore

@Suite("TranscriptSpeakerMatcher")
struct TranscriptSpeakerMatcherTests {
    private let meetingStart = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("단일 화자는 모든 겹친 전사 구간에 같은 라벨을 붙인다")
    func singleSpeakerMatchesAllSegments() {
        let matcher = TranscriptSpeakerMatcher()
        let transcript = [
            segment(offset: 0, duration: 3),
            segment(offset: 3, duration: 4),
        ]

        let matched = matcher.assignSpeakers(
            diarizedSegments: [diarized("speaker-a", start: 0, end: 10)],
            transcript: transcript,
            meetingStart: meetingStart
        )

        #expect(matched.map(\.speaker) == ["화자 1", "화자 1"])
        #expect(matched.map(\.id) == transcript.map(\.id))
        #expect(matched.map(\.words) == transcript.map(\.words))
    }

    @Test("두 화자 교대 구간은 가장 많이 겹친 화자를 선택한다")
    func alternatingSpeakersMatchByLargestOverlap() {
        let matcher = TranscriptSpeakerMatcher()
        let transcript = [
            segment(offset: 0, duration: 3),
            segment(offset: 3, duration: 3),
            segment(offset: 6, duration: 3),
        ]

        let matched = matcher.assignSpeakers(
            diarizedSegments: [
                diarized("speaker-a", start: 0, end: 3),
                diarized("speaker-b", start: 3, end: 6),
                diarized("speaker-a", start: 6, end: 9),
            ],
            transcript: transcript,
            meetingStart: meetingStart
        )

        #expect(matched.map(\.speaker) == ["화자 1", "화자 2", "화자 1"])
    }

    @Test("최소 겹침 비율 미만이면 speaker를 nil로 둔다")
    func insufficientOverlapLeavesSpeakerNil() {
        let matcher = TranscriptSpeakerMatcher(minimumOverlapRatio: 0.5)
        let transcript = [segment(offset: 0, duration: 4)]

        let matched = matcher.assignSpeakers(
            diarizedSegments: [diarized("speaker-a", start: 0, end: 1)],
            transcript: transcript,
            meetingStart: meetingStart
        )

        #expect(matched.map(\.speaker) == [nil])
    }

    @Test("겹침이 동률이면 더 이른 화자를 선택한다")
    func tieBreaksByEarlierSpeaker() {
        let matcher = TranscriptSpeakerMatcher(minimumOverlapRatio: 0.5)
        let transcript = [segment(offset: 0, duration: 4)]

        let matched = matcher.assignSpeakers(
            diarizedSegments: [
                diarized("speaker-a", start: 0, end: 2),
                diarized("speaker-b", start: 2, end: 4),
            ],
            transcript: transcript,
            meetingStart: meetingStart
        )

        #expect(matched.map(\.speaker) == ["화자 1"])
    }

    @Test("화자 번호는 speakerId 첫 등장 순서로 안정적으로 매핑된다")
    func speakerLabelsUseFirstAppearanceOrder() {
        let matcher = TranscriptSpeakerMatcher()
        let transcript = [
            segment(offset: 0, duration: 2),
            segment(offset: 2, duration: 2),
            segment(offset: 4, duration: 2),
        ]

        let matched = matcher.assignSpeakers(
            diarizedSegments: [
                diarized("remote-42", start: 0, end: 2),
                diarized("remote-7", start: 2, end: 4),
                diarized("remote-42", start: 4, end: 6),
            ],
            transcript: transcript,
            meetingStart: meetingStart
        )

        #expect(matched.map(\.speaker) == ["화자 1", "화자 2", "화자 1"])
    }

    @Test("화자 번호는 배열 순서가 아니라 시작 시각 순으로 매겨진다")
    func speakerLabelsFollowStartTimeNotArrayOrder() {
        let matcher = TranscriptSpeakerMatcher()
        let transcript = [
            segment(offset: 0, duration: 2),
            segment(offset: 2, duration: 2),
        ]

        // DiarizationResult.segments가 시작 시각순 정렬을 보장하지 않으므로,
        // 배열에 늦게 시작한 화자를 먼저 넣어도 번호는 시작 시각순(먼저 말한 사람=화자 1)이어야 한다.
        let matched = matcher.assignSpeakers(
            diarizedSegments: [
                diarized("late-speaker", start: 2, end: 4),
                diarized("early-speaker", start: 0, end: 2),
            ],
            transcript: transcript,
            meetingStart: meetingStart
        )

        #expect(matched.map(\.speaker) == ["화자 1", "화자 2"])
    }

    private func segment(offset: TimeInterval, duration: TimeInterval) -> Segment {
        Segment(
            id: UUID(),
            text: "전사 \(offset)",
            timestamp: meetingStart.addingTimeInterval(offset),
            duration: duration,
            speaker: "기존 라벨",
            words: [WordTimestamp(word: "전사", start: offset, end: offset + 0.5)]
        )
    }

    private func diarized(_ speakerId: String, start: Double, end: Double) -> DiarizedSpeakerSegment {
        DiarizedSpeakerSegment(speakerId: speakerId, startSeconds: start, endSeconds: end)
    }
}
