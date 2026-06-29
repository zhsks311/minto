import EventKit
import Foundation

public protocol RemindersServiceProtocol: Sendable {
    func requestAccess() async -> Bool
    func addReminder(title: String, dueDate: Date?, notes: String?) async throws
}

public actor RemindersService: RemindersServiceProtocol {
    private let eventStore: EKEventStore

    public init() {
        eventStore = EKEventStore()
    }

    public func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            if !granted {
                Log.reminders.error("reminders access denied")
            }
            return granted
        } catch {
            Log.reminders.error("reminders access failed error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    public func addReminder(title: String, dueDate: Date?, notes: String?) async throws {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        if let dueDate {
            reminder.dueDateComponents = Self.dueDateComponents(from: dueDate)
        }

        try eventStore.save(reminder, commit: true)
        let dueState = dueDate == nil ? "none" : "set"
        Log.reminders.info("reminder add succeeded due=\(dueState, privacy: .public)")
    }

    private static func dueDateComponents(from date: Date) -> DateComponents {
        var components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        components.calendar = Calendar(identifier: .gregorian)
        return components
    }
}

final class RemindersServiceStub: RemindersServiceProtocol, @unchecked Sendable {
    struct AddedReminder: Equatable, Sendable {
        var title: String
        var dueDate: Date?
        var notes: String?

        init(title: String, dueDate: Date?, notes: String?) {
            self.title = title
            self.dueDate = dueDate
            self.notes = notes
        }
    }

    var isAccessGranted: Bool
    var addError: Error?
    private(set) var addedReminders: [AddedReminder]

    init(isAccessGranted: Bool = true, addError: Error? = nil, addedReminders: [AddedReminder] = []) {
        self.isAccessGranted = isAccessGranted
        self.addError = addError
        self.addedReminders = addedReminders
    }

    func requestAccess() async -> Bool {
        isAccessGranted
    }

    func addReminder(title: String, dueDate: Date?, notes: String?) async throws {
        if let addError {
            throw addError
        }
        addedReminders.append(AddedReminder(title: title, dueDate: dueDate, notes: notes))
    }
}
