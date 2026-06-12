import Foundation

enum MeetingRecordFactory {
    @MainActor
    static func makeRecord(
        summary: MeetingSummary,
        segments: [Segment],
        topic: String,
        preferredTitle: String? = nil,
        fallbackTitle: String = "회의 결과",
        duration: TimeInterval,
        startedAt fallbackStart: Date = Date(),
        audioFileName: String? = nil
    ) -> MeetingRecord {
        let transcript = TranscriptNormalizer.normalize(segments)
        let title = resolvedTitle(
            summary: summary,
            preferredTitle: preferredTitle,
            topic: topic,
            fallbackTitle: fallbackTitle
        )
        let start = transcript.first?.timestamp ?? fallbackStart

        let meetingSeconds: TimeInterval
        if let first = transcript.first, let last = transcript.last {
            meetingSeconds = max(duration, last.timestamp.timeIntervalSince(first.timestamp) + last.duration)
        } else {
            meetingSeconds = duration
        }

        return MeetingRecord(
            title: title,
            startedAt: start,
            durationSeconds: meetingSeconds,
            topic: topic,
            summary: summary,
            transcript: transcript,
            audioFileName: audioFileName
        )
    }

    private static func resolvedTitle(
        summary: MeetingSummary,
        preferredTitle: String?,
        topic: String,
        fallbackTitle: String
    ) -> String {
        let summaryTitle = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summaryTitle.isEmpty { return summaryTitle }

        let preferred = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty { return preferred }

        let topicTrimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !topicTrimmed.isEmpty { return topicTrimmed }

        return fallbackTitle
    }
}
