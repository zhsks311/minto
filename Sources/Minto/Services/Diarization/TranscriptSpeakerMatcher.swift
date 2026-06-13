import Foundation

public struct TranscriptSpeakerMatcher: Sendable {
    public let minimumOverlapRatio: Double

    public init(minimumOverlapRatio: Double = 0.5) {
        self.minimumOverlapRatio = minimumOverlapRatio
    }

    public func assignSpeakers(
        diarizedSegments: [DiarizedSpeakerSegment],
        transcript: [Segment],
        meetingStart: Date
    ) -> [Segment] {
        let timeline = diarizedSegments.filter { $0.endSeconds > $0.startSeconds }
        let labelMap = Self.makeSpeakerLabelMap(from: timeline)

        return transcript.map { segment in
            let speaker = bestSpeaker(
                for: segment,
                meetingStart: meetingStart,
                timeline: timeline
            ).flatMap { labelMap[$0] }

            // Word-level alignment is a later pass; this matcher assigns a speaker per transcript segment.
            return Segment(
                id: segment.id,
                text: segment.text,
                timestamp: segment.timestamp,
                duration: segment.duration,
                speaker: speaker,
                words: segment.words
            )
        }
    }

    private func bestSpeaker(
        for segment: Segment,
        meetingStart: Date,
        timeline: [DiarizedSpeakerSegment]
    ) -> String? {
        guard segment.duration > 0 else { return nil }

        let transcriptStart = segment.timestamp.timeIntervalSince(meetingStart)
        let transcriptEnd = transcriptStart + segment.duration
        guard transcriptEnd > transcriptStart else { return nil }

        var overlaps: [String: SpeakerOverlap] = [:]
        for diarized in timeline {
            let seconds = Self.overlapSeconds(
                start: transcriptStart,
                end: transcriptEnd,
                otherStart: diarized.startSeconds,
                otherEnd: diarized.endSeconds
            )
            guard seconds > 0 else { continue }

            var current = overlaps[diarized.speakerId] ?? SpeakerOverlap()
            current.seconds += seconds
            current.earliestStart = min(current.earliestStart, diarized.startSeconds)
            overlaps[diarized.speakerId] = current
        }

        guard let best = overlaps.sorted(by: Self.isHigherPriority).first else {
            return nil
        }
        let overlapRatio = best.value.seconds / segment.duration
        guard overlapRatio >= minimumOverlapRatio else { return nil }
        return best.key
    }

    private static func makeSpeakerLabelMap(
        from segments: [DiarizedSpeakerSegment]
    ) -> [String: String] {
        var labels: [String: String] = [:]
        for segment in segments where labels[segment.speakerId] == nil {
            labels[segment.speakerId] = "화자 \(labels.count + 1)"
        }
        return labels
    }

    private static func overlapSeconds(
        start: Double,
        end: Double,
        otherStart: Double,
        otherEnd: Double
    ) -> Double {
        max(0, min(end, otherEnd) - max(start, otherStart))
    }

    private static func isHigherPriority(
        _ lhs: (key: String, value: SpeakerOverlap),
        than rhs: (key: String, value: SpeakerOverlap)
    ) -> Bool {
        if lhs.value.seconds != rhs.value.seconds {
            return lhs.value.seconds > rhs.value.seconds
        }
        if lhs.value.earliestStart != rhs.value.earliestStart {
            return lhs.value.earliestStart < rhs.value.earliestStart
        }
        return lhs.key < rhs.key
    }
}

private struct SpeakerOverlap {
    var seconds: Double = 0
    var earliestStart: Double = .infinity
}
