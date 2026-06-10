import Testing
@testable import MintoCore
import Foundation

/// MeetingSaveRecovery — 저장 실패 시 복구 파일 생성 경로 분류 테스트.
@MainActor
@Suite("MeetingSaveRecovery", .serialized)
struct MeetingSaveRecoveryTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-recovery-\(UUID().uuidString)", isDirectory: true)
    }

    private func sampleRecord(withTranscript: Bool = true) -> MeetingRecord {
        MeetingRecord(
            title: "테스트 회의",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 60,
            topic: "주제",
            summary: MeetingSummary(leadAnswer: "요약"),
            transcript: withTranscript
                ? [Segment(text: "안녕하세요", timestamp: Date(timeIntervalSince1970: 1_700_000_000), duration: 3)]
                : []
        )
    }

    // MARK: - (b) 디스크 실패 경로: 복구 파일 생성

    @Test("복구 파일이 지정 디렉터리에 생성된다")
    func writesRecoveryFileToDirectory() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let record = sampleRecord()
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: dir)

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let mdFiles = files.filter { $0.pathExtension == "md" }
        #expect(mdFiles.count == 1)
    }

    @Test("복구 파일명에 회의 ID와 .md 확장자가 포함된다")
    func recoveryFilenameContainsID() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let record = sampleRecord()
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: dir)

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let mdFile = files.first { $0.pathExtension == "md" }
        let filename = mdFile?.lastPathComponent ?? ""
        #expect(filename.contains(record.id.uuidString))
        #expect(filename.hasSuffix(".md"))
    }

    @Test("복구 파일 내용에 전사 텍스트가 포함된다")
    func recoveryFileContainsTranscript() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let record = sampleRecord(withTranscript: true)
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: dir)

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let mdFile = try #require(files.first { $0.pathExtension == "md" })
        let content = try String(contentsOf: mdFile, encoding: .utf8)
        #expect(content.contains("안녕하세요"))
        #expect(content.contains("## 전사"))
    }

    @Test("복구 파일 내용에 회의 제목이 포함된다")
    func recoveryFileContainsTitle() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let record = sampleRecord()
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: dir)

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let mdFile = try #require(files.first { $0.pathExtension == "md" })
        let content = try String(contentsOf: mdFile, encoding: .utf8)
        #expect(content.contains("# 테스트 회의"))
    }

    // MARK: - buildMarkdown 유닛 테스트 (내부 함수 @testable 접근)

    @Test("buildMarkdown: 전사 없는 회의는 전사 섹션 생략")
    func buildMarkdownSkipsEmptyTranscript() {
        let record = sampleRecord(withTranscript: false)
        let md = MeetingSaveRecovery.buildMarkdown(for: record)
        #expect(!md.contains("## 전사"))
    }

    @Test("buildMarkdown: 빈 제목이면 기본값 '회의' 사용")
    func buildMarkdownFallbackTitle() {
        let record = MeetingRecord(
            title: "",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 30,
            summary: MeetingSummary(leadAnswer: "요약"),
            transcript: []
        )
        let md = MeetingSaveRecovery.buildMarkdown(for: record)
        #expect(md.hasPrefix("# 회의\n"))
    }

    // MARK: - MeetingStore.save() 실패 경로 분류 확인

    @Test("MeetingStore.save: 빈 회의는 .skippedEmpty 반환")
    func storeReturnsSkippedEmptyForBlankRecord() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let empty = MeetingRecord(title: "x", startedAt: Date(), durationSeconds: 0)
        #expect(store.save(empty) == .skippedEmpty)
    }

    @Test("MeetingStore.save: 내용 있는 회의는 .success 반환")
    func storeReturnsSuccessForValidRecord() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        #expect(store.save(sampleRecord()) == .success)
    }

    @Test("MeetingStore.save: 쓰기 불가 경로는 .failed 반환")
    func storeReturnsFailedForUnwritableDirectory() {
        // /dev/null 하위 경로는 디렉터리가 아니므로 data.write가 실패한다.
        let unwritable = URL(fileURLWithPath: "/dev/null/nonexistent-\(UUID().uuidString)")
        let store = MeetingStore(directory: unwritable)
        #expect(store.save(sampleRecord()) == .failed)
    }

    // MARK: - JSON 왕복 테스트

    @Test("writeRecoveryFile: .json 파일이 생성되고 디코딩 후 id가 일치한다")
    func jsonRoundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let record = sampleRecord()
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: dir)

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let jsonFile = try #require(files.first { $0.pathExtension == "json" })
        let data = try Data(contentsOf: jsonFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(MeetingRecord.self, from: data)
        #expect(restored.id == record.id)
    }

    // MARK: - restorePendingRecords 테스트

    @Test("restorePendingRecords: 복원 성공 시 .json과 .md 모두 삭제된다")
    func restoreSuccessDeletesBothFiles() throws {
        let recoveryDir = tempDir()
        let storeDir = tempDir()
        defer {
            try? FileManager.default.removeItem(at: recoveryDir)
            try? FileManager.default.removeItem(at: storeDir)
        }

        let record = sampleRecord()
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: recoveryDir)

        let store = MeetingStore(directory: storeDir)
        let count = MeetingSaveRecovery.restorePendingRecords(into: store, recoveryDirectory: recoveryDir)

        #expect(count == 1)
        let remaining = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        #expect(remaining.isEmpty)
        #expect(store.meetings.contains { $0.id == record.id })
    }

    @Test("restorePendingRecords: store 재저장 실패 시 파일이 유지된다")
    func restoreFailRetainsFile() throws {
        let recoveryDir = tempDir()
        defer { try? FileManager.default.removeItem(at: recoveryDir) }

        let record = sampleRecord()
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: recoveryDir)

        // 쓰기 불가 경로로 store를 초기화해 .failed 유도
        let unwritable = URL(fileURLWithPath: "/dev/null/nonexistent-\(UUID().uuidString)")
        let failingStore = MeetingStore(directory: unwritable)
        let count = MeetingSaveRecovery.restorePendingRecords(into: failingStore, recoveryDirectory: recoveryDir)

        #expect(count == 0)
        let remaining = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        let jsonFiles = remaining.filter { $0.pathExtension == "json" }
        #expect(jsonFiles.count == 1)
        // 복원 실패 시 .md도 유지되어야 한다(사용자가 수동 회수 가능).
        let mdFiles = remaining.filter { $0.pathExtension == "md" }
        #expect(mdFiles.count == 1)
    }

    @Test("restorePendingRecords: 손상 JSON은 skip하고 정상 파일은 계속 처리한다")
    func restoreCorruptJsonSkips() throws {
        let recoveryDir = tempDir()
        let storeDir = tempDir()
        defer {
            try? FileManager.default.removeItem(at: recoveryDir)
            try? FileManager.default.removeItem(at: storeDir)
        }

        // 손상 파일
        try FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
        let corruptURL = recoveryDir.appendingPathComponent("corrupt.json")
        try Data("not valid json".utf8).write(to: corruptURL)

        // 정상 파일
        let record = sampleRecord()
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: recoveryDir)

        let store = MeetingStore(directory: storeDir)
        let count = MeetingSaveRecovery.restorePendingRecords(into: store, recoveryDirectory: recoveryDir)

        // 정상 파일 1건은 복원, 손상 파일은 유지
        #expect(count == 1)
        let remaining = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        #expect(remaining.count == 1)
        #expect(remaining[0].lastPathComponent == "corrupt.json")
    }

    @Test("restorePendingRecords: 빈 디렉터리에서 크래시 없이 0을 반환한다")
    func restoreEmptyDirectoryIsNoop() throws {
        let recoveryDir = tempDir()
        let storeDir = tempDir()
        defer {
            try? FileManager.default.removeItem(at: recoveryDir)
            try? FileManager.default.removeItem(at: storeDir)
        }

        try FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
        let store = MeetingStore(directory: storeDir)
        let count = MeetingSaveRecovery.restorePendingRecords(into: store, recoveryDirectory: recoveryDir)
        #expect(count == 0)
    }
}
