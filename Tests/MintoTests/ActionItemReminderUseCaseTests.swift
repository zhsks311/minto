import Foundation
import Testing
@testable import MintoCore

@Suite("ActionItemReminderUseCase")
struct ActionItemReminderUseCaseTests {
    private struct AddFailure: LocalizedError {
        var errorDescription: String? { "add failed" }
    }

    @Test("빈 목록은 빈 결과를 돌려준다")
    func emptyItemsReturnEmptyResults() async {
        let service = RemindersServiceStub()
        let useCase = ActionItemReminderUseCase(remindersService: service)

        let results = await useCase.export(items: [], meetingTitle: "주간 회의")

        #expect(results.isEmpty)
        #expect(service.addedReminders.isEmpty)
    }

    @Test("빈 task 항목은 내보내지 않는다")
    func blankTaskItemsAreSkipped() async {
        let service = RemindersServiceStub()
        let useCase = ActionItemReminderUseCase(remindersService: service)
        let blank = MeetingSummary.ActionItem(task: "   ", owner: "지민", due: "2026-06-30")

        let results = await useCase.export(items: [blank], meetingTitle: "주간 회의")

        #expect(results.isEmpty)
        #expect(service.addedReminders.isEmpty)
    }

    @Test("권한 거부는 실패 결과로 반환하고 reminder를 추가하지 않는다")
    func accessDeniedReturnsFailures() async {
        let service = RemindersServiceStub(isAccessGranted: false)
        let useCase = ActionItemReminderUseCase(remindersService: service)
        let item = MeetingSummary.ActionItem(task: "체크리스트 정리")

        let results = await useCase.export(items: [item], meetingTitle: "주간 회의")

        #expect(results == [
            ActionItemExportResult(actionItem: item, success: false, errorDescription: "Reminders access denied")
        ])
        #expect(service.addedReminders.isEmpty)
    }

    @Test("service throw는 실패 결과로 반환한다")
    func addThrowReturnsFailure() async {
        let service = RemindersServiceStub(addError: AddFailure())
        let useCase = ActionItemReminderUseCase(remindersService: service)
        let item = MeetingSummary.ActionItem(task: "체크리스트 정리")

        let results = await useCase.export(items: [item], meetingTitle: "주간 회의")

        #expect(results.count == 1)
        #expect(results[0].actionItem == item)
        #expect(results[0].success == false)
        #expect(results[0].errorDescription == "add failed")
        #expect(service.addedReminders.isEmpty)
    }

    @Test("due 파싱 실패는 nil dueDate로 reminder를 추가한다")
    func invalidDueAddsReminderWithoutDueDate() async throws {
        let service = RemindersServiceStub()
        let useCase = ActionItemReminderUseCase(remindersService: service)
        let item = MeetingSummary.ActionItem(task: "체크리스트 정리", owner: "지민", due: "다음 회의", time: "00:30")

        let results = await useCase.export(items: [item], meetingTitle: "주간 회의")

        #expect(results == [ActionItemExportResult(actionItem: item, success: true)])
        let added = try #require(service.addedReminders.first)
        #expect(added.title == "체크리스트 정리")
        #expect(added.dueDate == nil)
        #expect(added.notes?.contains("주간 회의") == true)
        #expect(added.notes?.contains("체크리스트 정리") == true)
    }
}
