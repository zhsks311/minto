import Foundation

/// 첨부 문서에서 요약 프롬프트에 넣을 정적 발췌문을 고른다.
///
/// LLM 호출 없이 문서 내 도메인 용어 밀도가 높은 문단을 우선 선택한다.
public enum DocumentContextSelector {
    private struct Paragraph {
        let index: Int
        let text: String
        let score: Int
    }

    private struct SelectedParagraph {
        let index: Int
        let text: String
    }

    private static let termLimit = 50
    private static let paragraphSeparator = "\n\n"

    public static func excerpt(from document: String, maxCharacters: Int) -> String {
        let trimmedDocument = document.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocument.isEmpty else { return "" }
        guard maxCharacters > 0 else { return "" }
        guard document.count > maxCharacters else { return document }

        let terms = Set(
            DocumentTermExtractor
                .extract(from: document, existingTerms: [], limit: termLimit)
                .map(DocumentTermExtractor.comparableText)
                .filter { !$0.isEmpty }
        )
        guard !terms.isEmpty else {
            return String(document.prefix(maxCharacters))
        }

        let paragraphs = splitDocument(document)
        guard !paragraphs.isEmpty else {
            return String(document.prefix(maxCharacters))
        }

        let rankedParagraphs = paragraphs
            .enumerated()
            .map { index, text in
                Paragraph(index: index, text: text, score: score(text, terms: terms))
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.index < rhs.index
            }

        let selected = selectParagraphs(rankedParagraphs, maxCharacters: maxCharacters)
        guard !selected.isEmpty else {
            return String(document.prefix(maxCharacters))
        }

        return selected
            .sorted { $0.index < $1.index }
            .map(\.text)
            .joined(separator: paragraphSeparator)
    }

    private static func splitDocument(_ document: String) -> [String] {
        let paragraphs = splitByBlankLines(document)
        if paragraphs.count > 1 {
            return paragraphs
        }
        return splitByLines(document)
    }

    private static func splitByBlankLines(_ document: String) -> [String] {
        var paragraphs: [String] = []
        var currentLines: [String] = []

        document.enumerateLines { line, _ in
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendParagraph(from: &currentLines, to: &paragraphs)
            } else {
                currentLines.append(line)
            }
        }
        appendParagraph(from: &currentLines, to: &paragraphs)

        return paragraphs
    }

    private static func splitByLines(_ document: String) -> [String] {
        var lines: [String] = []
        document.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }
        return lines
    }

    private static func appendParagraph(from currentLines: inout [String], to paragraphs: inout [String]) {
        let paragraph = currentLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !paragraph.isEmpty {
            paragraphs.append(paragraph)
        }
        currentLines.removeAll(keepingCapacity: true)
    }

    private static func score(_ paragraph: String, terms: Set<String>) -> Int {
        let comparableParagraph = DocumentTermExtractor.comparableText(paragraph)
        guard !comparableParagraph.isEmpty else { return 0 }

        return terms.reduce(0) { count, term in
            comparableParagraph.contains(term) ? count + 1 : count
        }
    }

    private static func selectParagraphs(
        _ paragraphs: [Paragraph],
        maxCharacters: Int
    ) -> [SelectedParagraph] {
        var selected: [SelectedParagraph] = []
        var usedCharacters = 0

        for paragraph in paragraphs {
            let separatorLength = selected.isEmpty ? 0 : paragraphSeparator.count
            let remainingCharacters = maxCharacters - usedCharacters - separatorLength
            guard remainingCharacters > 0 else { break }

            if paragraph.text.count <= remainingCharacters {
                selected.append(SelectedParagraph(index: paragraph.index, text: paragraph.text))
                usedCharacters += separatorLength + paragraph.text.count
            } else {
                selected.append(
                    SelectedParagraph(
                        index: paragraph.index,
                        text: String(paragraph.text.prefix(remainingCharacters))
                    )
                )
                break
            }
        }

        return selected
    }
}
