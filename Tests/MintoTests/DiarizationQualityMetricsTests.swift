import Foundation
import Testing
@testable import MintoCore

@Suite("DiarizationQualityMetrics")
struct DiarizationQualityMetricsTests {
    private let meetingStart = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("speaker 수, switch 수, transcript coverage, 평균 overlap을 계산한다")
    func calculatesDisplayGateMetrics() {
        let metrics = DiarizationQualityMetrics.calculate(
            diarizedSegments: [
                diarized("speaker-a", start: 0, end: 4),
                diarized("speaker-b", start: 4, end: 8),
            ],
            matchedTranscript: [
                segment(offset: 0, duration: 4, speaker: "화자 1"),
                segment(offset: 4, duration: 4, speaker: "화자 2"),
                segment(offset: 8, duration: 2, speaker: nil),
            ],
            meetingStart: meetingStart
        )

        #expect(metrics.diarizedSegmentCount == 2)
        #expect(metrics.uniqueSpeakerCount == 2)
        #expect(metrics.transcriptSegmentCount == 3)
        #expect(metrics.labeledTranscriptSegmentCount == 2)
        #expect(metrics.speakerSwitchCount == 1)
        #expect(metrics.transcriptCoverage == 2.0 / 3.0)
        #expect(metrics.transcriptTimeCoverage == 0.8)
        #expect(metrics.averageOverlapRatio == 1.0)
    }

    @Test("평균 overlap은 라벨이 붙은 구간의 speaker timeline 겹침 비율이다")
    func averageOverlapUsesMatchedSpeakerTimeline() {
        let metrics = DiarizationQualityMetrics.calculate(
            diarizedSegments: [diarized("speaker-a", start: 0, end: 2)],
            matchedTranscript: [segment(offset: 0, duration: 4, speaker: "화자 1")],
            meetingStart: meetingStart
        )

        #expect(metrics.transcriptCoverage == 1)
        #expect(metrics.averageOverlapRatio == 0.5)
    }

    private func segment(offset: TimeInterval, duration: TimeInterval, speaker: String?) -> Segment {
        Segment(
            text: "전사 \(offset)",
            timestamp: meetingStart.addingTimeInterval(offset),
            duration: duration,
            speaker: speaker
        )
    }

    private func diarized(_ speakerId: String, start: Double, end: Double) -> DiarizedSpeakerSegment {
        DiarizedSpeakerSegment(speakerId: speakerId, startSeconds: start, endSeconds: end)
    }
}
