import Foundation
@preconcurrency import EventKit

public protocol CalendarServiceProtocol: Sendable {
    func requestAccess() async -> Bool
    func upcomingEvents(within interval: TimeInterval) async -> [CalendarEvent]
}

public struct CalendarEvent: Sendable, Equatable {
    public let identifier: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let attendeeNames: [String]

    public init(
        identifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        attendeeNames: [String] = []
    ) {
        self.identifier = identifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.attendeeNames = attendeeNames
    }
}

public actor CalendarService: CalendarServiceProtocol {
    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    public func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            Log.calendar.info("calendar access granted=\(true, privacy: .public)")
            return true
        case .denied, .restricted, .writeOnly:
            Log.calendar.info("calendar access granted=\(false, privacy: .public)")
            return false
        case .notDetermined:
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                Log.calendar.info("calendar access granted=\(granted, privacy: .public)")
                return granted
            } catch {
                Log.calendar.error("calendar access request failed error=\(error.localizedDescription, privacy: .public)")
                return false
            }
        @unknown default:
            Log.calendar.error("calendar access status unknown")
            return false
        }
    }

    public func upcomingEvents(within interval: TimeInterval) async -> [CalendarEvent] {
        guard interval > 0 else {
            return []
        }
        guard await requestAccess() else {
            return []
        }

        let now = Date()
        let endDate = now.addingTimeInterval(interval)
        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEvent(
                    identifier: event.calendarItemIdentifier,
                    title: event.title ?? "",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    attendeeNames: (event.attendees ?? []).compactMap(\.name)
                )
            }

        Log.calendar.info("calendar upcoming events count=\(events.count, privacy: .public)")
        return events
    }
}

public final class CalendarServiceStub: CalendarServiceProtocol, @unchecked Sendable {
    private let accessGranted: Bool
    private let events: [CalendarEvent]

    public init(accessGranted: Bool = true, events: [CalendarEvent] = []) {
        self.accessGranted = accessGranted
        self.events = events
    }

    public func requestAccess() async -> Bool {
        accessGranted
    }

    public func upcomingEvents(within interval: TimeInterval) async -> [CalendarEvent] {
        accessGranted && interval > 0 ? events : []
    }
}
