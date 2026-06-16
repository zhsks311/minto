import Foundation

public struct DiarizationQualityMetrics: Sendable, Equatable {
    public let diarizedSegmentCount: Int
    public let uniqueSpeakerCount: Int
    public let transcriptSegmentCount: Int
    public let labeledTranscriptSegmentCount: Int
    public let speakerSwitchCount: Int
    public let transcriptCoverage: Double
    public let transcriptTimeCoverage: Double
    public let averageOverlapRatio: Double

    public init(
        diarizedSegmentCount: Int,
        uniqueSpeakerCount: Int,
        transcriptSegmentCount: Int,
        labeledTranscriptSegmentCount: Int,
        speakerSwitchCount: Int,
        transcriptCoverage: Double,
        transcriptTimeCoverage: Double,
        averageOverlapRatio: Double
    ) {
        self.diarizedSegmentCount = diarizedSegmentCount
        self.uniqueSpeakerCount = uniqueSpeakerCount
        self.transcriptSegmentCount = transcriptSegmentCount
        self.labeledTranscriptSegmentCount = labeledTranscriptSegmentCount
        self.speakerSwitchCount = speakerSwitchCount
        self.transcriptCoverage = transcriptCoverage
        self.transcriptTimeCoverage = transcriptTimeCoverage
        self.averageOverlapRatio = averageOverlapRatio
    }

    public static func calculate(
        diarizedSegments: [DiarizedSpeakerSegment],
        matchedTranscript: [Segment],
        meetingStart: Date
    ) -> DiarizationQualityMetrics {
        let timeline = diarizedSegments.filter { $0.endSeconds > $0.startSeconds }
        let labels = DiarizationSpeakerLabeling.makeLabelMap(from: timeline)
        let segmentsByLabel = Dictionary(grouping: timeline) { labels[$0.speakerId] ?? $0.speakerId }

        let labeledSegments = matchedTranscript.filter { normalizedSpeaker($0.speaker) != nil }
        let totalDuration = matchedTranscript.reduce(0) { $0 + max(0, $1.duration) }
        let labeledDuration = labeledSegments.reduce(0) { $0 + max(0, $1.duration) }
        let overlapRatios = labeledSegments.map { segment in
            overlapRatio(
                for: segment,
                meetingStart: meetingStart,
                candidateSegments: segmentsByLabel[normalizedSpeaker(segment.speaker) ?? ""] ?? []
            )
        }

        return DiarizationQualityMetrics(
            diarizedSegmentCount: timeline.count,
            uniqueSpeakerCount: Set(timeline.map(\.speakerId)).count,
            transcriptSegmentCount: matchedTranscript.count,
            labeledTranscriptSegmentCount: labeledSegments.count,
            speakerSwitchCount: speakerSwitchCount(in: matchedTranscript),
            transcriptCoverage: ratio(labeledSegments.count, matchedTranscript.count),
            transcriptTimeCoverage: totalDuration > 0 ? labeledDuration / totalDuration : 0,
            averageOverlapRatio: overlapRatios.isEmpty ? 0 : overlapRatios.reduce(0, +) / Double(overlapRatios.count)
        )
    }

    private static func speakerSwitchCount(in transcript: [Segment]) -> Int {
        var previousSpeaker: String?
        var switches = 0
        for speaker in transcript.compactMap({ normalizedSpeaker($0.speaker) }) {
            if let previousSpeaker, previousSpeaker != speaker {
                switches += 1
            }
            previousSpeaker = speaker
        }
        return switches
    }

    private static func overlapRatio(
        for segment: Segment,
        meetingStart: Date,
        candidateSegments: [DiarizedSpeakerSegment]
    ) -> Double {
        guard segment.duration > 0 else { return 0 }
        let transcriptStart = segment.timestamp.timeIntervalSince(meetingStart)
        let transcriptEnd = transcriptStart + segment.duration
        let overlap = candidateSegments.reduce(0) { total, diarized in
            total + max(0, min(transcriptEnd, diarized.endSeconds) - max(transcriptStart, diarized.startSeconds))
        }
        return min(1, overlap / segment.duration)
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        denominator > 0 ? Double(numerator) / Double(denominator) : 0
    }

    private static func normalizedSpeaker(_ speaker: String?) -> String? {
        guard let speaker = speaker?.trimmingCharacters(in: .whitespacesAndNewlines),
              !speaker.isEmpty else {
            return nil
        }
        return speaker
    }
}
