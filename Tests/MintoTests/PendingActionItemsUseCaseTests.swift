import Foundation
import Testing
@testable import MintoCore

@Suite("PendingActionItemsUseCase")
struct PendingActionItemsUseCaseTests {
    private let useCase = PendingActionItemsUseCase()

    @Test("다건 회의에서 isDone false 항목만 포함하고 항목 순서를 유지한다")
    func includesOnlyPendingItemsAcrossMeetings() {
        let first = record(
            title: "프로젝트 주간 회의",
            startedAt: Date(timeIntervalSince1970: 200),
            actionItems: [
                .init(task: "검색 UX 정리"),
                .init(task: "완료된 항목", isDone: true),
                .init(task: "QA 시나리오 업데이트")
            ]
        )
        let second = record(
            title: "디자인 리뷰",
            startedAt: Date(timeIntervalSince1970: 100),
            actionItems: [
                .init(task: "와이어프레임 피드백 반영", isDone: false)
            ]
        )

        let groups = useCase.pendingActionItems(from: [first, second])

        #expect(groups.count == 2)
        #expect(groups[0].items.map(\.actionItem.task) == ["검색 UX 정리", "QA 시나리오 업데이트"])
        #expect(groups[1].items.map(\.actionItem.task) == ["와이어프레임 피드백 반영"])
    }

    @Test("blank task는 제외한다")
    func excludesBlankTasks() {
        let meeting = record(actionItems: [
            .init(task: "   "),
            .init(task: "\n\t"),
            .init(task: "자료 공유")
        ])

        let groups = useCase.pendingActionItems(from: [meeting])

        #expect(groups.count == 1)
        #expect(groups[0].items.map(\.actionItem.task) == ["자료 공유"])
    }

    @Test("전체 완료 시 빈 결과를 반환한다")
    func returnsEmptyWhenAllDone() {
        let meeting = record(actionItems: [
            .init(task: "완료 A", isDone: true),
            .init(task: "완료 B", isDone: true)
        ])

        let groups = useCase.pendingActionItems(from: [meeting])

        #expect(groups.isEmpty)
    }

    @Test("회의는 최신 startedAt 순서로 정렬한다")
    func sortsMeetingsNewestFirst() {
        let older = record(title: "이전 회의", startedAt: Date(timeIntervalSince1970: 100))
        let newer = record(title: "최신 회의", startedAt: Date(timeIntervalSince1970: 300))
        let middle = record(title: "중간 회의", startedAt: Date(timeIntervalSince1970: 200))

        let groups = useCase.pendingActionItems(from: [older, newer, middle])

        #expect(groups.map(\.meetingTitle) == ["최신 회의", "중간 회의", "이전 회의"])
    }

    private func record(
        id: UUID = UUID(),
        title: String = "회의",
        startedAt: Date = Date(timeIntervalSince1970: 100),
        actionItems: [MeetingSummary.ActionItem] = [.init(task: "할일")]
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: title,
            startedAt: startedAt,
            durationSeconds: 60,
            summary: MeetingSummary(actionItems: actionItems)
        )
    }
}
