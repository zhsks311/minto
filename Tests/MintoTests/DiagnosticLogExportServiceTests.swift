import Foundation
import Testing
@testable import MintoCore

@Suite("Diagnostic log export service")
struct DiagnosticLogExportServiceTests {

    @Test("진단 로그 항목을 기존 export 텍스트 형식으로 변환한다")
    func formatsEntriesAsDiagnosticLogText() {
        let entries = [
            DiagnosticLogExportEntry(
                date: Date(timeIntervalSince1970: 0),
                category: "app",
                message: "log export success lines=2"
            ),
            DiagnosticLogExportEntry(
                date: Date(timeIntervalSince1970: 1),
                category: "search",
                message: "answer failed reason=network"
            ),
        ]

        let text = DiagnosticLogExportService.format(entries: entries)

        #expect(
            text == """
            [1970-01-01 00:00:00 +0000] [app] log export success lines=2
            [1970-01-01 00:00:01 +0000] [search] answer failed reason=network
            """
        )
    }

    @Test("빈 로그 항목은 빈 텍스트로 변환한다")
    func formatsEmptyEntriesAsEmptyText() {
        #expect(DiagnosticLogExportService.format(entries: []) == "")
    }
}
