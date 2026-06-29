import Foundation

public struct ActionItemExportResult: Equatable, Sendable {
    public var actionItem: MeetingSummary.ActionItem
    public var success: Bool
    public var errorDescription: String?

    public init(actionItem: MeetingSummary.ActionItem, success: Bool, errorDescription: String? = nil) {
        self.actionItem = actionItem
        self.success = success
        self.errorDescription = errorDescription
    }
}

public struct ActionItemReminderUseCase: Sendable {
    private let remindersService: any RemindersServiceProtocol
    private let calendar: Calendar

    public init(
        remindersService: any RemindersServiceProtocol = RemindersService(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.remindersService = remindersService
        self.calendar = calendar
    }

    public func export(items: [MeetingSummary.ActionItem], meetingTitle: String) async -> [ActionItemExportResult] {
        let exportableItems = items.filter { !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        Log.reminders.info("reminder export started count=\(exportableItems.count, privacy: .public)")
        guard !exportableItems.isEmpty else { return [] }

        guard await remindersService.requestAccess() else {
            Log.reminders.error("reminder export access denied count=\(exportableItems.count, privacy: .public)")
            return exportableItems.map {
                ActionItemExportResult(actionItem: $0, success: false, errorDescription: "Reminders access denied")
            }
        }

        var results: [ActionItemExportResult] = []
        results.reserveCapacity(exportableItems.count)
        for item in exportableItems {
            do {
                try await remindersService.addReminder(
                    title: item.task.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueDate: parseDueDate(item.due),
                    notes: reminderNotes(for: item, meetingTitle: meetingTitle)
                )
                results.append(ActionItemExportResult(actionItem: item, success: true))
            } catch {
                Log.reminders.error("reminder export item failed error=\(error.localizedDescription, privacy: .public)")
                results.append(ActionItemExportResult(actionItem: item, success: false, errorDescription: error.localizedDescription))
            }
        }

        let successCount = results.filter(\.success).count
        Log.reminders.info("reminder export completed count=\(exportableItems.count, privacy: .public) success=\(successCount, privacy: .public) failure=\(exportableItems.count - successCount, privacy: .public)")
        return results
    }

    private func parseDueDate(_ due: String) -> Date? {
        let trimmed = due.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: trimmed)
    }

    private func reminderNotes(for item: MeetingSummary.ActionItem, meetingTitle: String) -> String? {
        let task = item.task.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = item.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = item.due.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = item.time.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        if !title.isEmpty { lines.append("회의: \(title)") }
        if !task.isEmpty { lines.append("할 일: \(task)") }
        if !owner.isEmpty { lines.append("담당: \(owner)") }
        if !due.isEmpty { lines.append("기한: \(due)") }
        if !time.isEmpty { lines.append("시점: \(time)") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
