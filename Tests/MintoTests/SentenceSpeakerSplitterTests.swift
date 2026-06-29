import Foundation
import Testing
@testable import MintoCore

@Suite("SentenceSpeakerSplitter")
struct SentenceSpeakerSplitterTests {
    private let meetingStart = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("한 청크 안 두 화자 교대는 두 세그먼트로 분할된다")
    func alternatingSpeakersSplitIntoTwo() {
        let original = segment(
            offset: 0,
            words: [("가", 0, 1), ("나", 1, 2), ("다", 2, 3), ("라", 3, 4), ("마", 4, 5), ("바", 5, 6)]
        )
        let result = SentenceSpeakerSplitter().split(
            transcript: [original],
            diarizedSegments: [diarized("spk-a", 0, 3), diarized("spk-b", 3, 6)],
            meetingStart: meetingStart
        )

        #expect(result.count == 2)
        #expect(result.map(\.speaker) == ["화자 1", "화자 2"])
        #expect(result[0].id == original.id)
        #expect(result[1].id != original.id)
        #expect(result[0].text == "가 나 다")
        #expect(result[1].text == "라 마 바")
    }

    @Test("단일 화자라도 문장 종결 부호에서 분리된다")
    func singleSpeakerSplitsOnSentenceTerminator() {
        let original = segment(
            offset: 0,
            words: [("안녕", 0, 1), ("하세요.", 1, 2), ("다음", 2, 3), ("문장", 3, 4)]
        )
        let result = SentenceSpeakerSplitter().split(
            transcript: [original],
            diarizedSegments: [diarized("spk-a", 0, 6)],
            meetingStart: meetingStart
        )

        #expect(result.count == 2)
        #expect(result.map(\.speaker) == ["화자 1", "화자 1"])
        #expect(result[0].text == "안녕 하세요.")
        #expect(result[1].text == "다음 문장")
    }

    @Test("같은 화자라도 침묵 갭에서 분리된다")
    func singleSpeakerSplitsOnSilenceGap() {
        let original = segment(
            offset: 0,
            words: [("가", 0, 1), ("나", 1, 2), ("다", 2.6, 3.6), ("라", 3.6, 4.6)]
        )
        let result = SentenceSpeakerSplitter(silenceGapSeconds: 0.5).split(
            transcript: [original],
            diarizedSegments: [diarized("spk-a", 0, 6)],
            meetingStart: meetingStart
        )

        #expect(result.count == 2)
        #expect(result[0].text == "가 나")
        #expect(result[1].text == "다 라")
    }

    @Test("words가 nil이면 분할하지 않고 그대로 통과한다")
    func nilWordsPassThrough() {
        let original = Segment(
            text: "전사 원문",
            timestamp: meetingStart,
            duration: 5,
            speaker: "기존 라벨",
            words: nil
        )
        let result = SentenceSpeakerSplitter().split(
            transcript: [original],
            diarizedSegments: [diarized("spk-a", 0, 5)],
            meetingStart: meetingStart
        )

        #expect(result.count == 1)
        #expect(result[0].id == original.id)
        #expect(result[0].speaker == "기존 라벨")
        #expect(result[0].words == nil)
    }

    @Test("diarization 타임라인이 비면 분할하지 않는다")
    func emptyTimelinePassThrough() {
        let original = segment(
            offset: 0,
            words: [("가", 0, 1), ("나", 1, 2)],
            speaker: "기존 라벨"
        )
        let result = SentenceSpeakerSplitter().split(
            transcript: [original],
            diarizedSegments: [],
            meetingStart: meetingStart
        )

        #expect(result.count == 1)
        #expect(result[0].id == original.id)
        #expect(result[0].speaker == "기존 라벨")
    }

    @Test("preserveSegmentIds에 있는 세그먼트는 분할하지 않는다")
    func preservedSegmentNotSplit() {
        let original = segment(
            offset: 0,
            words: [("가", 0, 1), ("나", 1, 2), ("다", 2, 3), ("라", 3, 4), ("마", 4, 5), ("바", 5, 6)],
            speaker: "사용자 편집"
        )
        let result = SentenceSpeakerSplitter().split(
            transcript: [original],
            diarizedSegments: [diarized("spk-a", 0, 3), diarized("spk-b", 3, 6)],
            meetingStart: meetingStart,
            preserveSegmentIds: [original.id]
        )

        #expect(result.count == 1)
        #expect(result[0].id == original.id)
        #expect(result[0].speaker == "사용자 편집")
    }

    @Test("최소 길이 미만 화자 run은 인접 화자에 흡수된다")
    func shortSpeakerRunAbsorbed() {
        let original = segment(
            offset: 0,
            words: [("가", 0, 1), ("나", 1, 2), ("다", 2, 3), ("라", 3, 4), ("마", 4, 5), ("바", 5, 6)]
        )
        // 인덱스 3(3~4초)만 spk-b 구간 → run 길이 1 < 2 → 앞 화자(spk-a)에 흡수
        let result = SentenceSpeakerSplitter(minWordsPerSpeakerRun: 2).split(
            transcript: [original],
            diarizedSegments: [diarized("spk-a", 0, 3), diarized("spk-b", 3, 4), diarized("spk-a", 4, 6)],
            meetingStart: meetingStart
        )

        #expect(result.count == 1)
        #expect(result[0].speaker == "화자 1")
    }

    @Test("분할된 세그먼트의 words는 자기 timestamp 기준으로 재베이스된다")
    func splitWordsAreRebased() {
        let original = segment(
            offset: 10,
            words: [("가", 0, 1), ("나", 1, 2), ("다", 2, 3), ("라", 3, 4), ("마", 4, 5), ("바", 5, 6)]
        )
        let result = SentenceSpeakerSplitter().split(
            transcript: [original],
            diarizedSegments: [diarized("spk-a", 10, 13), diarized("spk-b", 13, 16)],
            meetingStart: meetingStart
        )

        #expect(result.count == 2)
        let second = result[1]
        #expect(second.words?.first?.start == 0)
        // 둘째 세그먼트 첫 단어(원본 인덱스 3, 청크 상대 3초)의 절대 위치 보존
        // = meetingStart + 청크오프셋(10) + 3 = meetingStart + 13
        let expectedAbsolute = meetingStart.addingTimeInterval(13)
        #expect(abs(second.timestamp.timeIntervalSince(expectedAbsolute)) < 0.0001)
    }

    @Test("화자 번호는 배열 순서가 아니라 시작 시각 순으로 매겨진다")
    func labelsFollowStartTimeNotArrayOrder() {
        let original = segment(
            offset: 0,
            words: [("가", 0, 1), ("나", 1, 2), ("다", 2, 3), ("라", 3, 4), ("마", 4, 5), ("바", 5, 6)]
        )
        let result = SentenceSpeakerSplitter().split(
            transcript: [original],
            // 늦게 시작한 화자를 배열에 먼저 넣어도, 먼저 말한 사람이 "화자 1"
            diarizedSegments: [diarized("late", 3, 6), diarized("early", 0, 3)],
            meetingStart: meetingStart
        )

        #expect(result.count == 2)
        #expect(result.map(\.speaker) == ["화자 1", "화자 2"])
    }

    @Test("여러 입력 세그먼트의 순서가 보존된다 (분할 + 폴백 혼재)")
    func multipleSegmentsPreserveOrder() {
        let splitting = segment(
            offset: 0,
            words: [("가", 0, 1), ("나", 1, 2), ("다", 2, 3), ("라", 3, 4), ("마", 4, 5), ("바", 5, 6)]
        )
        let passthrough = Segment(
            text: "통과 세그먼트",
            timestamp: meetingStart.addingTimeInterval(6),
            duration: 2,
            speaker: "기존 라벨",
            words: nil
        )
        let result = SentenceSpeakerSplitter().split(
            transcript: [splitting, passthrough],
            diarizedSegments: [diarized("spk-a", 0, 3), diarized("spk-b", 3, 6)],
            meetingStart: meetingStart
        )

        #expect(result.count == 3)
        #expect(result[0].id == splitting.id)
        #expect(result[1].id != splitting.id)
        #expect(result[2].id == passthrough.id)
        #expect(result[2].text == "통과 세그먼트")
    }

    @Test("종결 부호와 화자 전환이 같은 지점이면 경계는 한 번만 생긴다")
    func terminatorAtSpeakerChangeIsSingleBoundary() {
        let original = segment(
            offset: 0,
            words: [("시작", 0, 1), ("끝.", 1, 2), ("다시", 2, 3), ("시작", 3, 4)]
        )
        // 인덱스 0,1 = spk-a / 2,3 = spk-b. 인덱스 1("끝.")이 종결부호 + 직후 화자 전환
        let result = SentenceSpeakerSplitter().split(
            transcript: [original],
            diarizedSegments: [diarized("spk-a", 0, 2), diarized("spk-b", 2, 4)],
            meetingStart: meetingStart
        )

        #expect(result.count == 2)
        #expect(result.map(\.speaker) == ["화자 1", "화자 2"])
        #expect(result[0].text == "시작 끝.")
        #expect(result[1].text == "다시 시작")
    }

    @Test("어떤 단어도 화자 구간과 안 겹치면 폴백하고 원본 speaker를 보존한다")
    func allWordsUnmatchedFallbackKeepsSpeaker() {
        let original = segment(
            offset: 0,
            words: [("가", 0, 1), ("나", 1, 2), ("다", 2, 3)],
            speaker: "기존 라벨"
        )
        // diarization 구간이 전사 단어들과 전혀 겹치지 않는다(100초 이후)
        let result = SentenceSpeakerSplitter().split(
            transcript: [original],
            diarizedSegments: [diarized("spk-a", 100, 106)],
            meetingStart: meetingStart
        )

        #expect(result.count == 1)
        #expect(result[0].id == original.id)
        #expect(result[0].speaker == "기존 라벨")
    }

    private func segment(
        offset: TimeInterval,
        words: [(String, TimeInterval, TimeInterval)],
        speaker: String = "기존 라벨"
    ) -> Segment {
        let duration = words.last.map { $0.2 } ?? 0
        return Segment(
            text: words.map(\.0).joined(separator: " "),
            timestamp: meetingStart.addingTimeInterval(offset),
            duration: duration,
            speaker: speaker,
            words: words.map { WordTimestamp(word: $0.0, start: $0.1, end: $0.2) }
        )
    }

    private func diarized(_ speakerId: String, _ start: Double, _ end: Double) -> DiarizedSpeakerSegment {
        DiarizedSpeakerSegment(speakerId: speakerId, startSeconds: start, endSeconds: end)
    }
}
