import Foundation

/// 교정 전후 텍스트의 보수적 diff에서 용어집 별칭 후보를 추출한다.
///
/// LLM을 호출하지 않는 순수 규칙이다. 교정문 쪽을 canonical, 원문 쪽을 alias로 본다.
public enum CorrectionAliasExtractor {
    public static func extract(raw: String, corrected: String) -> [(canonical: String, alias: String)] {
        let rawTokens = tokenize(raw)
        let correctedTokens = tokenize(corrected)
        guard !rawTokens.isEmpty, !correctedTokens.isEmpty else { return [] }

        let anchors = lcsAnchors(
            raw: rawTokens.map(\.comparable),
            corrected: correctedTokens.map(\.comparable)
        )

        var results: [(canonical: String, alias: String)] = []
        var seen = Set<String>()
        var rawStart = 0
        var correctedStart = 0

        for anchor in anchors {
            appendCandidate(
                rawTokens: Array(rawTokens[rawStart..<anchor.rawIndex]),
                correctedTokens: Array(correctedTokens[correctedStart..<anchor.correctedIndex]),
                into: &results,
                seen: &seen
            )
            rawStart = anchor.rawIndex + 1
            correctedStart = anchor.correctedIndex + 1
        }

        appendCandidate(
            rawTokens: Array(rawTokens[rawStart..<rawTokens.count]),
            correctedTokens: Array(correctedTokens[correctedStart..<correctedTokens.count]),
            into: &results,
            seen: &seen
        )

        return results
    }

    private struct Token {
        let raw: String
        let comparable: String
    }

    private struct Anchor {
        let rawIndex: Int
        let correctedIndex: Int
    }

    private static func tokenize(_ text: String) -> [Token] {
        text.split(whereSeparator: { $0.isWhitespace }).compactMap { part in
            let raw = String(part)
            let comparable = DocumentTermExtractor.comparableText(raw)
            guard !comparable.isEmpty else { return nil }
            return Token(raw: raw, comparable: comparable)
        }
    }

    private static func appendCandidate(
        rawTokens: [Token],
        correctedTokens: [Token],
        into results: inout [(canonical: String, alias: String)],
        seen: inout Set<String>
    ) {
        guard (1...3).contains(rawTokens.count), (1...3).contains(correctedTokens.count) else { return }

        let alias = cleanedPhrase(rawTokens.map(\.raw))
        let canonical = cleanedPhrase(correctedTokens.map(\.raw))
        guard DocumentTermExtractor.isLongEnough(alias), DocumentTermExtractor.isLongEnough(canonical) else { return }
        guard isAllowedPair(alias: alias, canonical: canonical, aliasTokenCount: rawTokens.count, canonicalTokenCount: correctedTokens.count) else { return }

        let key = "\(DocumentTermExtractor.comparableText(canonical))\u{1f}\(DocumentTermExtractor.comparableText(alias))"
        guard !seen.contains(key) else { return }
        seen.insert(key)
        results.append((canonical: canonical, alias: alias))
    }

    private static func lcsAnchors(raw: [String], corrected: [String]) -> [Anchor] {
        let rawCount = raw.count
        let correctedCount = corrected.count
        var lengths = Array(
            repeating: Array(repeating: 0, count: correctedCount + 1),
            count: rawCount + 1
        )

        if rawCount > 0, correctedCount > 0 {
            for rawIndex in stride(from: rawCount - 1, through: 0, by: -1) {
                for correctedIndex in stride(from: correctedCount - 1, through: 0, by: -1) {
                    if raw[rawIndex] == corrected[correctedIndex] {
                        lengths[rawIndex][correctedIndex] = lengths[rawIndex + 1][correctedIndex + 1] + 1
                    } else {
                        lengths[rawIndex][correctedIndex] = max(
                            lengths[rawIndex + 1][correctedIndex],
                            lengths[rawIndex][correctedIndex + 1]
                        )
                    }
                }
            }
        }

        var anchors: [Anchor] = []
        var rawIndex = 0
        var correctedIndex = 0
        while rawIndex < rawCount, correctedIndex < correctedCount {
            if raw[rawIndex] == corrected[correctedIndex] {
                anchors.append(Anchor(rawIndex: rawIndex, correctedIndex: correctedIndex))
                rawIndex += 1
                correctedIndex += 1
            } else if lengths[rawIndex + 1][correctedIndex] >= lengths[rawIndex][correctedIndex + 1] {
                rawIndex += 1
            } else {
                correctedIndex += 1
            }
        }
        return anchors
    }

    private static func cleanedPhrase(_ tokens: [String]) -> String {
        tokens
            .map { DocumentTermExtractor.trimPunctuationAndSymbols($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isAllowedPair(alias: String, canonical: String, aliasTokenCount: Int, canonicalTokenCount: Int) -> Bool {
        let aliasHasHangul = containsHangul(alias)
        let aliasIsPureHangulPhrase = isPureHangulPhrase(alias)
        let canonicalHasHangul = containsHangul(canonical)
        let aliasHasLatinOrDigit = containsLatinOrDigit(alias)
        let canonicalHasLatinOrDigit = containsLatinOrDigit(canonical)

        if aliasIsPureHangulPhrase, !canonicalHasHangul, canonicalHasLatinOrDigit {
            return true
        }

        return isSegmentedLatinOrDigitAlias(
            alias: alias,
            canonical: canonical,
            aliasTokenCount: aliasTokenCount,
            canonicalTokenCount: canonicalTokenCount,
            aliasHasHangul: aliasHasHangul,
            canonicalHasHangul: canonicalHasHangul,
            aliasHasLatinOrDigit: aliasHasLatinOrDigit,
            canonicalHasLatinOrDigit: canonicalHasLatinOrDigit
        )
    }

    private static func isSegmentedLatinOrDigitAlias(
        alias: String,
        canonical: String,
        aliasTokenCount: Int,
        canonicalTokenCount: Int,
        aliasHasHangul: Bool,
        canonicalHasHangul: Bool,
        aliasHasLatinOrDigit: Bool,
        canonicalHasLatinOrDigit: Bool
    ) -> Bool {
        guard !aliasHasHangul, !canonicalHasHangul else { return false }
        guard aliasHasLatinOrDigit, canonicalHasLatinOrDigit else { return false }
        guard aliasTokenCount > 1 || canonicalTokenCount > 1 else { return false }
        return DocumentTermExtractor.comparableText(alias) == DocumentTermExtractor.comparableText(canonical)
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            isHangul(scalar)
        }
    }

    private static func containsLatinOrDigit(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x30...0x39).contains(scalar.value)
                || (0x41...0x5A).contains(scalar.value)
                || (0x61...0x7A).contains(scalar.value)
        }
    }

    private static func isPureHangulPhrase(_ text: String) -> Bool {
        let scalars = text.unicodeScalars.filter { scalar in
            !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }
        var hasHangul = false
        for scalar in scalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            guard isHangul(scalar) else { return false }
            hasHangul = true
        }
        return hasHangul
    }

    private static func isHangul(_ scalar: UnicodeScalar) -> Bool {
        (0xAC00...0xD7A3).contains(scalar.value)
            || (0x1100...0x11FF).contains(scalar.value)
            || (0x3130...0x318F).contains(scalar.value)
    }
}
