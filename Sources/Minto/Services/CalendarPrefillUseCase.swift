import Foundation

public struct CalendarPrefillUseCase: Sendable {
    public init() {}

    public func findBestMatch(
        events: [CalendarEvent],
        relativeTo date: Date = Date(),
        window: TimeInterval = 900
    ) -> CalendarEvent? {
        guard window > 0 else { return nil }

        return events
            .filter { abs($0.startDate.timeIntervalSince(date)) <= window }
            .min {
                abs($0.startDate.timeIntervalSince(date)) < abs($1.startDate.timeIntervalSince(date))
            }
    }
}
