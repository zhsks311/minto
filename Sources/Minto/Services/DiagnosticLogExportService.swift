import Foundation
import OSLog

struct DiagnosticLogExportEntry: Equatable, Sendable {
    let date: Date
    let category: String
    let message: String
}

struct DiagnosticLogExportFile: Equatable, Sendable {
    let lineCount: Int
    fileprivate let content: String
}

enum DiagnosticLogExportServiceError: Error, Equatable, LocalizedError {
    case noEntries
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noEntries:
            return "내보낼 로그가 없어요."
        case .encodingFailed:
            return "로그 파일을 UTF-8로 변환하지 못했어요."
        }
    }
}

struct DiagnosticLogExportService: Sendable {
    func exportCurrentProcessLogs(to destinationURL: URL) throws -> Int {
        let exportFile = try makeCurrentProcessExportFile()
        try write(exportFile, to: destinationURL)
        return exportFile.lineCount
    }

    func makeCurrentProcessExportFile() throws -> DiagnosticLogExportFile {
        let entries = try currentProcessLogEntries()
        guard !entries.isEmpty else {
            throw DiagnosticLogExportServiceError.noEntries
        }

        let content = Self.format(entries: entries)
        return DiagnosticLogExportFile(lineCount: entries.count, content: content)
    }

    func write(_ exportFile: DiagnosticLogExportFile, to destinationURL: URL) throws {
        guard let data = exportFile.content.data(using: .utf8) else {
            throw DiagnosticLogExportServiceError.encodingFailed
        }

        try data.write(to: destinationURL, options: .atomic)
    }

    static func format(entries: [DiagnosticLogExportEntry]) -> String {
        entries
            .map { "[\($0.date)] [\($0.category)] \($0.message)" }
            .joined(separator: "\n")
    }

    private func currentProcessLogEntries() throws -> [DiagnosticLogExportEntry] {
        // scope: .currentProcessIdentifier — 현재 프로세스 세션 로그만 수집
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let subsystem = Bundle.main.bundleIdentifier ?? "com.minto.app"
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        // position(date:) 대신 프로세스 첫 항목부터 수집 (현재 실행 분만 해당)
        let entries = try store.getEntries(
            with: [],
            at: store.position(timeIntervalSinceLatestBoot: 0),
            matching: predicate
        )

        return entries.compactMap { entry in
            guard let logEntry = entry as? OSLogEntryLog else { return nil }
            // 주의: 같은 프로세스에서 읽는 composedMessage는 privacy 마스킹이
            // 적용되지 않은 원문이다. 내보내기 안전의 전제는 마스킹이 아니라
            // "Logger에 전사·주제·검색어·절대경로 같은 민감/식별 값을 넣지 않기"다.
            return DiagnosticLogExportEntry(
                date: logEntry.date,
                category: logEntry.category,
                message: logEntry.composedMessage
            )
        }
    }
}
