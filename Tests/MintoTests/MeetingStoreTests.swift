import Testing
@testable import MintoCore
import Foundation

/// MeetingStore 영속화 — temp 디렉터리로 실제 저장소를 건드리지 않는다.
@MainActor
@Suite("MeetingStore 영속화", .serialized)
struct MeetingStoreTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("minto-store-\(UUID().uuidString)", isDirectory: true)
    }

    private func sampleRecord(title: String = "회의", at seconds: TimeInterval = 1_700_000_000) -> MeetingRecord {
        MeetingRecord(
            title: title,
            startedAt: Date(timeIntervalSince1970: seconds),
            durationSeconds: 90,
            topic: "주제",
            summary: MeetingSummary(
                title: title,
                leadQuestion: "핵심?",
                leadAnswer: "요약",
                sections: [.init(title: "1. 주제", time: "00:10", points: [.init(text: "핵심", subPoints: ["세부"])])],
                keywords: ["k"],
                decisions: [.init(text: "결정", time: "00:20")],
                actionItems: [.init(task: "할 일", owner: "담당자", due: "내일", time: "00:30")],
                openQuestions: [.init(text: "질문", time: "00:40")]
            ),
            transcript: [Segment(text: "안녕하세요", timestamp: Date(timeIntervalSince1970: seconds), duration: 5)]
        )
    }

    @Test("save → 새 인스턴스 reload 라운드트립")
    func saveAndReload() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let rec = sampleRecord()
        #expect(store.save(rec) == .success)
        #expect(store.meetings.contains { $0.id == rec.id })

        let store2 = MeetingStore(directory: dir)
        let loaded = store2.meetings.first { $0.id == rec.id }
        #expect(loaded?.title == "회의")
        #expect(loaded?.summary.sections.first?.time == "00:10")
        #expect(loaded?.summary.sections.first?.points.first?.subPoints == ["세부"])
        #expect(loaded?.summary.decisions.first?.text == "결정")
        #expect(loaded?.summary.actionItems.first?.owner == "담당자")
        #expect(loaded?.summary.openQuestions.first?.time == "00:40")
        #expect(loaded?.transcript.first?.text == "안녕하세요")
    }

    @Test("MeetingRecordCoding 팩토리 encoder/decoder는 MeetingRecord를 보존한다")
    func codingFactoryRoundTripsMeetingRecord() throws {
        let record = sampleRecord()
        let data = try MeetingRecordCoding.makeEncoder().encode(record)
        let restored = try MeetingRecordCoding.makeDecoder().decode(MeetingRecord.self, from: data)

        #expect(restored == record)
    }

    @Test("빈 회의(전사·요약 없음)는 저장하지 않는다")
    func skipsEmpty() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let empty = MeetingRecord(title: "x", startedAt: Date(), durationSeconds: 0)
        #expect(store.save(empty) == .skippedEmpty)
        #expect(store.meetings.isEmpty)
    }

    @Test("삭제는 디스크에서도 제거")
    func deletes() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let rec = sampleRecord()
        store.save(rec)
        store.delete(rec.id)
        #expect(store.meetings.isEmpty)
        #expect(MeetingStore(directory: dir).meetings.isEmpty)
    }

    @Test("손상 JSON은 skip하고 정상만 로드")
    func skipsCorrupt() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ 깨진 json".write(to: dir.appendingPathComponent("\(UUID().uuidString).json"), atomically: true, encoding: .utf8)
        let store = MeetingStore(directory: dir)
        store.save(sampleRecord())
        #expect(store.meetings.count == 1)
    }

    @Test("목록은 최신순 정렬")
    func sortedDesc() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        store.save(sampleRecord(title: "old", at: 1000))
        store.save(sampleRecord(title: "new", at: 2000))
        #expect(store.meetings.first?.title == "new")
        #expect(store.meetings.last?.title == "old")
    }

    @Test("회의 저장은 검색 sidecar index를 갱신하고 중복 저장은 chunk를 중복하지 않는다")
    func saveUpdatesSearchIndexWithoutDuplicates() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let rec = sampleRecord()

        store.save(rec)
        store.save(rec)

        let index = MeetingSearchIndexStore(directory: dir).load()
        let chunks = index?.chunks.filter { $0.meetingID == rec.id } ?? []
        #expect(chunks.isEmpty == false)
        #expect(Set(chunks.map(\.id)).count == chunks.count)
    }

    @Test("회의 삭제는 검색 sidecar index에서도 chunk를 제거한다")
    func deleteUpdatesSearchIndex() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let rec = sampleRecord()

        store.save(rec)
        store.delete(rec.id)

        let index = MeetingSearchIndexStore(directory: dir).load()
        #expect(index?.chunks.contains { $0.meetingID == rec.id } == false)
    }

    @Test("손상된 검색 sidecar index는 reload 시 현재 회의 목록 기준으로 재생성된다")
    func reloadRebuildsCorruptSearchIndex() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let rec = sampleRecord()
        store.save(rec)

        try "corrupt".write(to: store.searchIndexURL, atomically: true, encoding: .utf8)
        _ = MeetingStore(directory: dir)

        let index = MeetingSearchIndexStore(directory: dir).load()
        #expect(index?.chunks.contains { $0.meetingID == rec.id } == true)
    }

    @Test("버전이 맞지 않는 검색 sidecar index는 reload 시 재생성된다")
    func reloadRebuildsIncompatibleSearchIndex() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let rec = sampleRecord()
        store.save(rec)

        let staleSnapshot = """
        {
          "chunks": [],
          "chunkingVersion": 999,
          "generatedAt": "2026-06-09T00:00:00Z",
          "schemaVersion": \(MeetingSearchIndex.schemaVersion)
        }
        """
        try staleSnapshot.write(to: store.searchIndexURL, atomically: true, encoding: .utf8)
        _ = MeetingStore(directory: dir)

        let index = MeetingSearchIndexStore(directory: dir).load()
        #expect(index?.chunks.contains { $0.meetingID == rec.id } == true)
    }

    @Test("검색 sidecar index 파일이 없어도 reload 시 재생성된다")
    func reloadRebuildsMissingSearchIndex() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let rec = sampleRecord()
        store.save(rec)

        try FileManager.default.removeItem(at: store.searchIndexURL)
        _ = MeetingStore(directory: dir)

        let index = MeetingSearchIndexStore(directory: dir).load()
        #expect(index?.chunks.contains { $0.meetingID == rec.id } == true)
    }
}
