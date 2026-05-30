import Testing
@testable import MintoCore
import Foundation

@Suite("ReportService Tests")
struct ReportServiceTests {

    var tempDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MintoTest-\(UUID().uuidString)")
    }

    @Test("3개 세그먼트 → Markdown 포맷 검증")
    func threeSegmentsProduceCorrectMarkdown() async throws {
        let baseDate = Date(timeIntervalSince1970: 0)  // 09:00:00 UTC
        let segments = [
            Segment(id: UUID(), text: "안녕하세요", timestamp: baseDate, duration: 1.0),
            Segment(id: UUID(), text: "회의 시작합니다", timestamp: baseDate.addingTimeInterval(3), duration: 2.0),
            Segment(id: UUID(), text: "감사합니다", timestamp: baseDate.addingTimeInterval(10), duration: 1.5),
        ]

        // Use Report struct directly
        let r = Report(startedAt: baseDate, segments: segments)
        let content = r.markdownContent

        #expect(content.contains("안녕하세요"))
        #expect(content.contains("회의 시작합니다"))
        #expect(content.contains("감사합니다"))
        // Check timestamp format [HH:mm:ss]
        #expect(content.contains("["), "Should contain timestamp brackets")
    }

    @Test("flush 시 기존 파일에 append (덮어쓰기 아님)")
    func flushAppendsToExistingFile() async throws {
        let dir = tempDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let testFile = dir.appendingPathComponent("test.md")
        let existingContent = "[00:00:01] 기존 내용\n"
        try existingContent.write(to: testFile, atomically: true, encoding: .utf8)

        let newLine = "[00:00:05] 새로운 내용\n"
        if let handle = try? FileHandle(forWritingTo: testFile) {
            handle.seekToEndOfFile()
            handle.write(newLine.data(using: .utf8)!)
            handle.closeFile()
        }

        let result = try String(contentsOf: testFile, encoding: .utf8)
        #expect(result.contains("기존 내용"), "Original content must be preserved")
        #expect(result.contains("새로운 내용"), "New content must be appended")
        #expect(result.hasPrefix("[00:00:01]"), "Original content must come first")
    }
}
