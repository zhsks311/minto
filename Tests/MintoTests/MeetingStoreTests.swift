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

    @Test("MeetingRecordCoding 팩토리 encoder/decoder는 schemaVersion과 모든 필드를 보존한다")
    func codingFactoryRoundTripsMeetingRecord() throws {
        var record = sampleRecord()
        record.schemaVersion = 2
        record.audioFileName = "meeting.wav"
        record.summaryGlossary = "Minto = 회의 기록 앱\nSwiftUI"
        record.document = "회의 자료 본문"
        let data = try MeetingRecordCoding.makeEncoder().encode(record)
        let restored = try MeetingRecordCoding.makeDecoder().decode(MeetingRecord.self, from: data)

        #expect(restored == record)
        #expect(restored.schemaVersion == 2)
        #expect(restored.audioFileName == "meeting.wav")
        #expect(restored.summaryGlossary == "Minto = 회의 기록 앱\nSwiftUI")
        #expect(restored.document == "회의 자료 본문")
    }

    @Test("summaryGlossary는 저장 라운드트립에서 보존된다")
    func roundTripsSummaryGlossary() throws {
        var record = sampleRecord()
        record.summaryGlossary = "루션 = 프로젝트명\nMinto = 회의 앱"

        let data = try MeetingRecordCoding.makeEncoder().encode(record)
        let restored = try MeetingRecordCoding.makeDecoder().decode(MeetingRecord.self, from: data)

        #expect(restored.summaryGlossary == "루션 = 프로젝트명\nMinto = 회의 앱")
    }

    @Test("빈 summaryGlossary는 nil로 정규화된다")
    func emptySummaryGlossaryNormalizesToNil() throws {
        let record = MeetingRecord(
            title: "회의",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 60,
            summary: MeetingSummary(leadAnswer: "요약"),
            summaryGlossary: " \n\t "
        )

        let data = try MeetingRecordCoding.makeEncoder().encode(record)
        let restored = try MeetingRecordCoding.makeDecoder().decode(MeetingRecord.self, from: data)

        let id = UUID()
        let jsonWithEmptyGlossary = """
        {
          "id": "\(id.uuidString)",
          "title": "회의",
          "startedAt": "2026-06-17T12:00:00Z",
          "summaryGlossary": " \\n\\t "
        }
        """
        let decoded = try MeetingRecordCoding.makeDecoder()
            .decode(MeetingRecord.self, from: Data(jsonWithEmptyGlossary.utf8))

        #expect(record.summaryGlossary == nil)
        #expect(restored.summaryGlossary == nil)
        #expect(decoded.summaryGlossary == nil)
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

    @Test("손상 JSON은 quarantine으로 이동하고 회의 목록에서 제외한다")
    func quarantinesCorruptJSON() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let record = sampleRecord()
        let recordData = try MeetingRecordCoding.makeEncoder().encode(record)
        try recordData.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))

        let corruptURL = dir.appendingPathComponent("corrupt.json")
        try Data("{ 깨진 json".utf8).write(to: corruptURL)

        let store = MeetingStore(directory: dir)
        #expect(store.meetings.count == 1)
        #expect(store.meetings.first?.id == record.id)
        #expect(store.corruptedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: corruptURL.path))

        let quarantinedURL = dir
            .appendingPathComponent("quarantine", isDirectory: true)
            .appendingPathComponent("corrupt.json")
        #expect(FileManager.default.fileExists(atPath: quarantinedURL.path))
    }

    @Test("키는 있으나 값이 손상된 JSON은 기본값으로 덮지 않고 quarantine한다")
    func quarantinesStructurallyCorruptValues() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // summary 키가 존재하지만 타입이 객체가 아니라 문자열 — decodeIfPresent가 throw해야 한다.
        // try?였다면 빈 MeetingSummary()로 조용히 덮여 부분 데이터가 유실됐을 경로.
        let id = UUID()
        let corruptSummaryJSON = """
        {
          "id": "\(id.uuidString)",
          "title": "요약 손상 회의",
          "startedAt": "2026-06-13T12:00:00Z",
          "summary": "this should be an object"
        }
        """
        let corruptURL = dir.appendingPathComponent("\(id.uuidString).json")
        try Data(corruptSummaryJSON.utf8).write(to: corruptURL)

        // id가 유효한 UUID 형식이 아니면 필수 필드 실패로 quarantine된다.
        let badIdJSON = """
        { "id": "not-a-uuid", "title": "회의", "startedAt": "2026-06-13T12:00:00Z" }
        """
        let badIdURL = dir.appendingPathComponent("bad-id.json")
        try Data(badIdJSON.utf8).write(to: badIdURL)

        let store = MeetingStore(directory: dir)
        #expect(store.meetings.isEmpty)
        #expect(store.corruptedCount == 2)
        // 원본은 삭제되지 않고 quarantine으로 이동되어야 한다 — 데이터 유실 방지.
        let quarantineDir = dir.appendingPathComponent("quarantine", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: corruptURL.path))
        #expect(!FileManager.default.fileExists(atPath: badIdURL.path))
        let quarantined = (try? FileManager.default.contentsOfDirectory(atPath: quarantineDir.path)) ?? []
        #expect(quarantined.count == 2)
    }

    @Test("이전 스키마 JSON은 누락된 필드를 기본값으로 채워 로드한다")
    func loadsOldSchemaWithDefaults() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let id = UUID()
        let startedAt = "2026-06-13T12:00:00Z"
        let oldSchemaJSON = """
        {
          "id": "\(id.uuidString)",
          "title": "이전 회의",
          "startedAt": "\(startedAt)"
        }
        """
        try Data(oldSchemaJSON.utf8).write(to: dir.appendingPathComponent("\(id.uuidString).json"))

        let store = MeetingStore(directory: dir)
        let loaded = try #require(store.meetings.first)
        #expect(loaded.id == id)
        #expect(loaded.title == "이전 회의")
        #expect(loaded.schemaVersion == 1)
        #expect(loaded.durationSeconds == 0)
        #expect(loaded.topic == "")
        #expect(loaded.summary == MeetingSummary())
        #expect(loaded.summaryGlossary == nil)
        #expect(loaded.document == nil)
        #expect(loaded.transcript == [])
        #expect(loaded.audioFileName == nil)
        #expect(store.corruptedCount == 0)
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
