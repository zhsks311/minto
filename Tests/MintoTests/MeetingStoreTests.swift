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
                keywords: ["k"]
            ),
            transcript: [Segment(text: "안녕하세요", timestamp: Date(timeIntervalSince1970: seconds), duration: 5)]
        )
    }

    @Test("save → 새 인스턴스 reload 라운드트립")
    func saveAndReload() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let rec = sampleRecord()
        #expect(store.save(rec) == true)
        #expect(store.meetings.contains { $0.id == rec.id })

        let store2 = MeetingStore(directory: dir)
        let loaded = store2.meetings.first { $0.id == rec.id }
        #expect(loaded?.title == "회의")
        #expect(loaded?.summary.sections.first?.time == "00:10")
        #expect(loaded?.summary.sections.first?.points.first?.subPoints == ["세부"])
        #expect(loaded?.transcript.first?.text == "안녕하세요")
    }

    @Test("빈 회의(전사·요약 없음)는 저장하지 않는다")
    func skipsEmpty() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let empty = MeetingRecord(title: "x", startedAt: Date(), durationSeconds: 0)
        #expect(store.save(empty) == false)
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
}
