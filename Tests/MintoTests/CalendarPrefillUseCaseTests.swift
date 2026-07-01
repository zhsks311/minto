import Foundation
import Testing
@testable import MintoCore

@Suite("CalendarPrefillUseCase")
struct CalendarPrefillUseCaseTests {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("빈 배열은 nil을 반환한다")
    func emptyEventsReturnNil() {
        let useCase = CalendarPrefillUseCase()

        let result = useCase.findBestMatch(events: [], relativeTo: baseDate)

        #expect(result == nil)
    }

    @Test("창 밖 이벤트는 nil을 반환한다")
    func eventOutsideWindowReturnsNil() {
        let useCase = CalendarPrefillUseCase()
        let event = makeEvent(identifier: "far", startOffset: 901)

        let result = useCase.findBestMatch(events: [event], relativeTo: baseDate, window: 900)

        #expect(result == nil)
    }

    @Test("창 안 단일 이벤트를 반환한다")
    func singleEventInsideWindowReturnsEvent() {
        let useCase = CalendarPrefillUseCase()
        let event = makeEvent(identifier: "near", startOffset: -900)

        let result = useCase.findBestMatch(events: [event], relativeTo: baseDate, window: 900)

        #expect(result == event)
    }

    @Test("복수 후보 중 기준 시각에 가장 가까운 이벤트를 반환한다")
    func multipleEventsReturnNearestEvent() {
        let useCase = CalendarPrefillUseCase()
        let earlier = makeEvent(identifier: "earlier", startOffset: -300)
        let nearest = makeEvent(identifier: "nearest", startOffset: 60)
        let later = makeEvent(identifier: "later", startOffset: 240)

        let result = useCase.findBestMatch(
            events: [earlier, nearest, later],
            relativeTo: baseDate,
            window: 900
        )

        #expect(result == nearest)
    }

    @Test("0 이하 window는 nil을 반환한다")
    func nonPositiveWindowReturnsNil() {
        let useCase = CalendarPrefillUseCase()
        let event = makeEvent(identifier: "now", startOffset: 0)

        let zero = useCase.findBestMatch(events: [event], relativeTo: baseDate, window: 0)
        let negative = useCase.findBestMatch(events: [event], relativeTo: baseDate, window: -1)

        #expect(zero == nil)
        #expect(negative == nil)
    }

    private func makeEvent(identifier: String, startOffset: TimeInterval) -> CalendarEvent {
        let startDate = baseDate.addingTimeInterval(startOffset)
        return CalendarEvent(
            identifier: identifier,
            title: "회의",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600)
        )
    }
}
