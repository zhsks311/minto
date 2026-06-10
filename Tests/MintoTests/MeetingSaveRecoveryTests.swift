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
        let filename = files.first?.lastPathComponent ?? ""
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
        let content = try String(contentsOf: files[0], encoding: .utf8)
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
        let content = try String(contentsOf: files[0], encoding: .utf8)
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
}
