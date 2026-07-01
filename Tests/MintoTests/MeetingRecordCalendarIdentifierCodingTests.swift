import Foundation
import Testing
@testable import MintoCore

@Suite("MeetingRecord calendar identifier coding")
struct MeetingRecordCalendarIdentifierCodingTests {
    @Test("calendarEventIdentifier 키 없는 이전 JSON은 nil로 로드된다")
    func loadsOldSchemaWithoutCalendarIdentifierAsNil() throws {
        let id = UUID()
        let oldSchemaJSON = """
        {
          "id": "\(id.uuidString)",
          "title": "이전 회의",
          "startedAt": "2026-06-29T01:00:00Z",
          "summary": { "leadAnswer": "요약" },
          "transcript": []
        }
        """

        let decoded = try MeetingRecordCoding.makeDecoder()
            .decode(MeetingRecord.self, from: Data(oldSchemaJSON.utf8))

        #expect(decoded.id == id)
        #expect(decoded.calendarEventIdentifier == nil)
    }

    @Test("calendarEventIdentifier 키가 있으면 값이 보존된다")
    func decodesCalendarIdentifierWhenPresent() throws {
        let id = UUID()
        let eventIdentifier = "calendar-item-123"
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "캘린더 회의",
          "startedAt": "2026-06-29T01:00:00Z",
          "calendarEventIdentifier": "\(eventIdentifier)",
          "summary": { "leadAnswer": "요약" },
          "transcript": []
        }
        """

        let decoded = try MeetingRecordCoding.makeDecoder()
            .decode(MeetingRecord.self, from: Data(json.utf8))

        #expect(decoded.calendarEventIdentifier == eventIdentifier)
    }

    @Test("calendarEventIdentifier 빈 문자열은 nil로 정규화된다")
    func normalizesBlankCalendarIdentifierAsNil() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "캘린더 회의",
          "startedAt": "2026-06-29T01:00:00Z",
          "calendarEventIdentifier": "   ",
          "summary": { "leadAnswer": "요약" },
          "transcript": []
        }
        """
        let initialized = MeetingRecord(
            title: "캘린더 회의",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 120,
            calendarEventIdentifier: "   "
        )

        let decoded = try MeetingRecordCoding.makeDecoder()
            .decode(MeetingRecord.self, from: Data(json.utf8))

        #expect(decoded.calendarEventIdentifier == nil)
        #expect(initialized.calendarEventIdentifier == nil)
    }

    @Test("calendarEventIdentifier는 JSON 라운드트립에서 보존된다")
    func roundTripsCalendarIdentifier() throws {
        let record = MeetingRecord(
            title: "캘린더 회의",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 120,
            topic: "캘린더 매칭",
            summary: MeetingSummary(leadAnswer: "요약"),
            calendarEventIdentifier: "calendar-item-456",
            transcript: []
        )

        let data = try MeetingRecordCoding.makeEncoder().encode(record)
        let restored = try MeetingRecordCoding.makeDecoder().decode(MeetingRecord.self, from: data)

        #expect(restored.calendarEventIdentifier == "calendar-item-456")
        #expect(restored == record)
    }
}
