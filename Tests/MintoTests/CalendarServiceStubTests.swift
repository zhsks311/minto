import Foundation
import Testing
@testable import MintoCore

@Suite("CalendarServiceStub")
struct CalendarServiceStubTests {
    @Test("권한 허용 시 configured events를 반환한다")
    func returnsEventsWhenAccessGranted() async {
        let event = CalendarEvent(
            identifier: "event-1",
            title: "주간 싱크",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            attendeeNames: ["A", "B"]
        )
        let service = CalendarServiceStub(events: [event])

        let granted = await service.requestAccess()
        let events = await service.upcomingEvents(within: 900)

        #expect(granted)
        #expect(events == [event])
    }

    @Test("0 이하 조회 범위는 빈 배열을 반환한다")
    func returnsEmptyEventsForNonPositiveInterval() async {
        let event = CalendarEvent(
            identifier: "event-1",
            title: "주간 싱크",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600)
        )
        let service = CalendarServiceStub(events: [event])

        let zero = await service.upcomingEvents(within: 0)
        let negative = await service.upcomingEvents(within: -1)

        #expect(zero.isEmpty)
        #expect(negative.isEmpty)
    }

    @Test("기준 시각 주변 과거 이벤트도 반환한다")
    func returnsPastEventsInsideSurroundingWindow() async {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let pastEvent = CalendarEvent(
            identifier: "past-event",
            title: "이미 시작한 회의",
            startDate: referenceDate.addingTimeInterval(-300),
            endDate: referenceDate.addingTimeInterval(3_300)
        )
        let outsideEvent = CalendarEvent(
            identifier: "outside-event",
            title: "너무 오래전 회의",
            startDate: referenceDate.addingTimeInterval(-1_200),
            endDate: referenceDate.addingTimeInterval(-900)
        )
        let service = CalendarServiceStub(events: [pastEvent, outsideEvent])

        let events = await service.events(around: referenceDate, window: 900)

        #expect(events == [pastEvent])
    }

    @Test("권한 거부 시 빈 배열을 반환한다")
    func returnsEmptyEventsWhenAccessDenied() async {
        let event = CalendarEvent(
            identifier: "event-1",
            title: "주간 싱크",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600)
        )
        let service = CalendarServiceStub(accessGranted: false, events: [event])

        let granted = await service.requestAccess()
        let events = await service.upcomingEvents(within: 900)

        #expect(!granted)
        #expect(events.isEmpty)
    }
}
