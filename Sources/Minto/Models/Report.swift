import Foundation

public struct Report: Sendable {
    public let meetingId: UUID
    public let startedAt: Date
    public var segments: [Segment]

    public init(meetingId: UUID = UUID(), startedAt: Date, segments: [Segment] = []) {
        self.meetingId = meetingId
        self.startedAt = startedAt
        self.segments = segments
    }

    public var markdownContent: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return segments
            .map { "[\(formatter.string(from: $0.timestamp))] \($0.text)" }
            .joined(separator: "\n")
    }

    public var fileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return "\(formatter.string(from: startedAt)).md"
    }
}
