import Foundation
import Testing
@testable import MintoCore

@Suite("ActionItem isDone coding")
struct ActionItemDoneCodingTests {
    @Test("isDone 키 없는 이전 JSON은 false로 decode된다")
    func missingIsDoneDecodesFalse() throws {
        let json = """
        {
          "task": "체크리스트 정리",
          "owner": "지민",
          "due": "2026-07-01",
          "time": "00:30"
        }
        """

        let item = try JSONDecoder().decode(MeetingSummary.ActionItem.self, from: Data(json.utf8))

        #expect(item.isDone == false)
    }

    @Test("isDone true JSON은 true로 decode된다")
    func isDoneTrueDecodesTrue() throws {
        let json = """
        {
          "task": "체크리스트 정리",
          "owner": "지민",
          "due": "2026-07-01",
          "time": "00:30",
          "isDone": true
        }
        """

        let item = try JSONDecoder().decode(MeetingSummary.ActionItem.self, from: Data(json.utf8))

        #expect(item.isDone == true)
    }
}
