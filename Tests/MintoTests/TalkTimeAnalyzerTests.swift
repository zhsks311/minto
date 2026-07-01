import Foundation
import Testing
@testable import MintoCore

@Suite("TalkTimeAnalyzer")
struct TalkTimeAnalyzerTests {
    private func segment(speaker: String?, duration: TimeInterval) -> Segment {
        Segment(
            text: "발언",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            duration: duration,
            speaker: speaker
        )
    }

    @Test("빈 배열은 빈 결과")
    func emptySegmentsReturnEmptyResult() {
        #expect(TalkTimeAnalyzer.analyze(segments: []).isEmpty)
    }

    @Test("단일 화자는 전체 시간을 하나로 합산한다")
    func singleSpeakerAggregatesAllDurations() {
        let result = TalkTimeAnalyzer.analyze(segments: [
            segment(speaker: "화자 1", duration: 10),
            segment(speaker: "화자 1", duration: 5),
        ])

        #expect(result == [
            SpeakerTalkTime(speakerLabel: "화자 1", seconds: 15, ratio: 1),
        ])
    }

    @Test("다화자 비율 합은 1에 가깝다")
    func multiSpeakerRatiosSumToOne() {
        let result = TalkTimeAnalyzer.analyze(segments: [
            segment(speaker: "화자 1", duration: 10),
            segment(speaker: "화자 2", duration: 30),
        ])

        #expect(result.map(\.speakerLabel) == ["화자 2", "화자 1"])
        #expect(abs(result.reduce(0) { $0 + $1.ratio } - 1) < 0.000001)
    }

    @Test("nil speaker는 알 수 없음 버킷으로 집계한다")
    func nilSpeakerAggregatesIntoUnknownBucket() throws {
        let result = TalkTimeAnalyzer.analyze(segments: [
            segment(speaker: nil, duration: 4),
            segment(speaker: "화자 1", duration: 3),
            segment(speaker: nil, duration: 6),
        ])

        let unknown = try #require(result.first { $0.speakerLabel == "알 수 없음" })
        #expect(unknown.seconds == 10)
    }

    @Test("duration 0 세그먼트는 seconds와 ratio에 반영된다")
    func zeroDurationSegmentsAreIncluded() {
        let mixed = TalkTimeAnalyzer.analyze(segments: [
            segment(speaker: "화자 1", duration: 0),
            segment(speaker: "화자 2", duration: 10),
        ])
        let zeroTotal = TalkTimeAnalyzer.analyze(segments: [
            segment(speaker: "화자 1", duration: 0),
            segment(speaker: "화자 2", duration: 0),
        ])

        #expect(mixed.first { $0.speakerLabel == "화자 1" }?.seconds == 0)
        #expect(mixed.first { $0.speakerLabel == "화자 1" }?.ratio == 0)
        #expect(zeroTotal.allSatisfy { $0.ratio == 0 })
    }

    @Test("seconds 내림차순으로 정렬한다")
    func sortsBySecondsDescending() {
        let result = TalkTimeAnalyzer.analyze(segments: [
            segment(speaker: "화자 1", duration: 5),
            segment(speaker: "화자 2", duration: 12),
            segment(speaker: "화자 3", duration: 7),
        ])

        #expect(result.map(\.speakerLabel) == ["화자 2", "화자 3", "화자 1"])
    }

    @Test("seconds 동률이면 라벨 오름차순으로 정렬한다")
    func sortsByLabelAscendingWhenSecondsTie() {
        let result = TalkTimeAnalyzer.analyze(segments: [
            segment(speaker: "화자 2", duration: 8),
            segment(speaker: "화자 1", duration: 8),
            segment(speaker: "화자 3", duration: 8),
        ])

        #expect(result.map(\.speakerLabel) == ["화자 1", "화자 2", "화자 3"])
    }
}
