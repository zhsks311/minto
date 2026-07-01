import Foundation

public struct PendingActionItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let meetingID: UUID
    public let meetingTitle: String
    public let meetingDate: Date
    public let meetingSubtitle: String
    public let actionItem: MeetingSummary.ActionItem

    public init(
        id: String,
        meetingID: UUID,
        meetingTitle: String,
        meetingDate: Date,
        meetingSubtitle: String,
        actionItem: MeetingSummary.ActionItem
    ) {
        self.id = id
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.meetingDate = meetingDate
        self.meetingSubtitle = meetingSubtitle
        self.actionItem = actionItem
    }
}

public struct PendingActionItemsGroup: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let meetingID: UUID
    public let meetingTitle: String
    public let meetingDate: Date
    public let meetingSubtitle: String
    public let items: [PendingActionItem]

    public init(
        meetingID: UUID,
        meetingTitle: String,
        meetingDate: Date,
        meetingSubtitle: String,
        items: [PendingActionItem]
    ) {
        self.id = meetingID
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.meetingDate = meetingDate
        self.meetingSubtitle = meetingSubtitle
        self.items = items
    }
}

public struct PendingActionItemsUseCase: Sendable {
    public init() {}

    public func pendingActionItems(from meetings: [MeetingRecord]) -> [PendingActionItemsGroup] {
        meetings
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { meeting in
                let title = displayTitle(for: meeting)
                let items = meeting.summary.actionItems.enumerated().compactMap { index, item -> PendingActionItem? in
                    guard !item.isDone,
                          !item.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }

                    return PendingActionItem(
                        id: "\(meeting.id.uuidString)-\(index)",
                        meetingID: meeting.id,
                        meetingTitle: title,
                        meetingDate: meeting.startedAt,
                        meetingSubtitle: meeting.subtitle,
                        actionItem: item
                    )
                }

                guard !items.isEmpty else { return nil }
                return PendingActionItemsGroup(
                    meetingID: meeting.id,
                    meetingTitle: title,
                    meetingDate: meeting.startedAt,
                    meetingSubtitle: meeting.subtitle,
                    items: items
                )
            }
    }

    private func displayTitle(for meeting: MeetingRecord) -> String {
        let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없음" : title
    }
}
