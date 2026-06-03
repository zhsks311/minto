import Foundation
import AppKit
import UniformTypeIdentifiers

/// 회의 결과를 표준 Markdown으로 내보낸다. Notion·Confluence 모두 표준 Markdown(헤딩·불릿·체크박스·인용)을
/// import/붙여넣기로 인식하므로, 별도 변환 없이 표준 MD를 생성한다(인증 연동은 후속).
public enum MeetingExporter {

    /// 제목 + 메타 + 구조화 요약 + 전사로 구성된 전체 Markdown 문서.
    public static func markdown(for result: MeetingResult) -> String {
        var out = "# \(result.title.isEmpty ? "회의" : result.title)\n\n"
        out += "_\(result.metaText)_\n\n"

        let summaryMd = result.summary.markdown()
        if !summaryMd.isEmpty {
            out += summaryMd + "\n\n"
        }
        if !result.transcript.isEmpty {
            out += "## 전사\n\n"
            out += result.transcript
                .map { "**[\($0.time)]** \($0.text)" }
                .joined(separator: "\n\n")
            out += "\n"
        }
        return out
    }

    /// 파일 시스템에 안전한 파일명(.md).
    public static func filename(for result: MeetingResult) -> String {
        let base = result.title.isEmpty ? "회의" : result.title
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let safe = base.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (safe.isEmpty ? "회의" : safe) + ".md"
    }

    /// NSSavePanel로 .md 저장. 취소·실패 시 nil.
    @MainActor
    @discardableResult
    public static func save(_ result: MeetingResult) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename(for: result)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.title = "회의록 내보내기"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try Data(markdown(for: result).utf8).write(to: url, options: .atomic)
            return url
        } catch {
            fputs("[Export] 저장 실패: \(error.localizedDescription)\n", stderr)
            return nil
        }
    }
}
