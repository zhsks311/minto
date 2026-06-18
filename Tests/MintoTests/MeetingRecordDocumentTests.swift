import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("MeetingRecord document persistence", .serialized)
struct MeetingRecordDocumentTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("minto-document-\(UUID().uuidString)", isDirectory: true)
    }

    private func segment(text: String = "회의 발언") -> Segment {
        Segment(
            text: text,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            duration: 5
        )
    }

    private func record(
        id: UUID = UUID(),
        summary: MeetingSummary = MeetingSummary(leadAnswer: "요약"),
        document: String? = "회의 자료"
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: "문서 회의",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 120,
            topic: "문서 영속화",
            summary: summary,
            document: document,
            transcript: [segment()],
            audioFileName: "meeting.wav"
        )
    }

    @Test("document는 JSON 라운드트립에서 보존된다")
    func roundTripsDocument() throws {
        let record = record(document: "첨부 회의 자료\n두 번째 줄")

        let data = try MeetingRecordCoding.makeEncoder().encode(record)
        let restored = try MeetingRecordCoding.makeDecoder().decode(MeetingRecord.self, from: data)

        #expect(restored.document == "첨부 회의 자료\n두 번째 줄")
        #expect(restored == record)
    }

    @Test("document 키 없는 이전 JSON은 nil로 로드된다")
    func loadsOldSchemaWithoutDocumentAsNil() throws {
        let id = UUID()
        let oldSchemaJSON = """
        {
          "id": "\(id.uuidString)",
          "title": "이전 회의",
          "startedAt": "2026-06-17T12:00:00Z",
          "summary": { "leadAnswer": "요약" },
          "transcript": []
        }
        """

        let decoded = try MeetingRecordCoding.makeDecoder()
            .decode(MeetingRecord.self, from: Data(oldSchemaJSON.utf8))

        #expect(decoded.id == id)
        #expect(decoded.document == nil)
    }

    @Test("공백뿐인 document는 nil로 정규화된다")
    func whitespaceOnlyDocumentNormalizesToNil() throws {
        let record = record(document: " \n\t ")

        let data = try MeetingRecordCoding.makeEncoder().encode(record)
        let restored = try MeetingRecordCoding.makeDecoder().decode(MeetingRecord.self, from: data)

        #expect(record.document == nil)
        #expect(restored.document == nil)
    }

    @Test("라이브 저장 wrapper는 MeetingContext document를 record에 전달한다")
    func liveMakeRecordPersistsMeetingContextDocument() {
        MeetingContext.shared.start(topic: "라이브 회의", glossary: "", document: "라이브 회의 자료")
        defer { MeetingContext.shared.clear() }

        let record = AppDelegate.makeRecord(
            summary: MeetingSummary(leadAnswer: "요약"),
            segments: [segment()],
            topic: MeetingContext.shared.topic,
            duration: 5,
            document: MeetingContext.shared.document
        )

        #expect(record.document == "라이브 회의 자료")
    }

    @Test("회의 자료 제거는 최신 record에 document만 병합하고 요약 변경은 보존한다")
    func removeDocumentMergesIntoLatestStoreRecord() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let original = record(document: "삭제할 회의 자료")
        #expect(store.save(original) == .success)

        var latest = try #require(store.meetings.first)
        latest.summary = MeetingSummary(leadAnswer: "문서 제거 전에 갱신된 요약")
        #expect(store.save(latest) == .success)

        #expect(MeetingDocumentRemoval.removeDocument(recordID: original.id, in: store) == .success)

        let saved = try #require(store.meetings.first)
        #expect(saved.id == original.id)
        #expect(saved.document == nil)
        #expect(saved.summary.leadAnswer == "문서 제거 전에 갱신된 요약")
        #expect(saved.transcript == original.transcript)
        #expect(saved.audioFileName == "meeting.wav")
    }
}
