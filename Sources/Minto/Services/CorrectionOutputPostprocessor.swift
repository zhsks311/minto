import Foundation

public enum CorrectionOutputPostprocessor {
    private static let outputMarkers = [
        "출력:",
        "최종 출력:",
        "교정 결과:",
        "교정본:",
        "수정 결과:",
        "수정본:"
    ]

    public static func clean(_ output: String) -> String {
        let trimmed = stripWrappingQuotes(output.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return trimmed }

        let lines = trimmed
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let markerMatch = firstOutputMarker(in: lines) else {
            return trimmed
        }

        var candidateLines = [markerMatch.text]
        if markerMatch.lineIndex + 1 < lines.count {
            candidateLines.append(contentsOf: lines[(markerMatch.lineIndex + 1)...])
        }

        let candidate = stripWrappingQuotes(
            candidateLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return candidate.isEmpty ? trimmed : candidate
    }

    private static func firstOutputMarker(in lines: [String]) -> (lineIndex: Int, text: String)? {
        for (lineIndex, line) in lines.enumerated() {
            for marker in outputMarkers {
                if line.hasPrefix(marker) {
                    let text = line.dropFirst(marker.count)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return (lineIndex, text)
                    }
                }
            }
        }
        return nil
    }

    private static func stripWrappingQuotes(_ value: String) -> String {
        var result = value
        let pairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("“", "”"),
            ("‘", "’")
        ]
        var didStrip = true
        while didStrip, result.count >= 2 {
            didStrip = false
            guard let first = result.first, let last = result.last else { break }
            for pair in pairs where first == pair.0 && last == pair.1 {
                result = String(result.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
                break
            }
        }
        return result
    }
}
