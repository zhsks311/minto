import os
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
                .map { line in
                    if let speaker = normalizedSpeaker(line.speaker) {
                        return "**[\(line.time)]** **\(escapeMarkdownControlCharacters(speaker)):** \(line.text)"
                    }
                    return "**[\(line.time)]** \(line.text)"
                }
                .joined(separator: "\n\n")
            out += "\n"
        }
        return out
    }

    /// 파일 시스템에 안전한 파일명(.md).
    public static func filename(for result: MeetingResult) -> String {
        let base = result.title.isEmpty ? "회의" : result.title
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var safe = base.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        safe = String(safe.prefix(80))   // 길이 제한(파일명 한도)
        // 빈 문자열·점만 있는 경우(숨김 파일/오류) 기본값으로.
        if safe.isEmpty || safe.allSatisfy({ $0 == "." }) {
            safe = "회의"
        }
        return safe + ".md"
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
            Log.store.error("export 저장 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func normalizedSpeaker(_ speaker: String?) -> String? {
        guard let speaker = speaker?.trimmingCharacters(in: .whitespacesAndNewlines),
              !speaker.isEmpty else {
            return nil
        }
        return speaker
    }

    private static func escapeMarkdownControlCharacters(_ text: String) -> String {
        let controlCharacters = Set("\\`*_{}[]<>()#+-.!|")
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            if controlCharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
