import Foundation
import NaturalLanguage

/// 첨부 문서에서 프롬프트에 넣을 용어를 정적으로 추출한다.
///
/// LLM을 호출하지 않는 순수 규칙이다. 추출 결과는 이번 회의 프롬프트 입력에만 쓰며
/// GlossaryStore 큐레이션 경로를 거치지 않는다.
public enum DocumentTermExtractor {
    private struct Candidate {
        var term: String
        var count: Int
        let firstLocation: Int
        var isHighConfidence: Bool
    }

    public static let defaultLimit = 24
    private static let asciiPattern = #"""
    (?<![A-Za-z0-9-])(?:[A-Z]{2,}(?:-[A-Z0-9]+)*|[A-Z][A-Za-z0-9]*[A-Z][A-Za-z0-9]*|[A-Z][A-Za-z0-9]{1,}|[A-Za-z]*\d+[A-Za-z0-9]*(?:-[A-Za-z0-9]+)+|[A-Za-z]+-\d+(?:-[A-Za-z0-9]+)*|[A-Za-z]+(?:-[A-Za-z0-9]+)+|\d+(?:-[A-Za-z0-9]+)+)(?![A-Za-z0-9-])
    """#
    private static let asciiExpression: NSRegularExpression? = try? NSRegularExpression(
        pattern: asciiPattern,
        options: [.allowCommentsAndWhitespace]
    )
    private static let foldLocale = Locale(identifier: "en_US_POSIX")

    // NaturalLanguage가 한국어 POS를 지원하지 않는 플랫폼에서 용언/조사 유입을 줄이는 휴리스틱이다.
    private static let koreanVerbEndings = [
        "한다", "된다", "했다", "됐다", "하면", "되면", "해야", "되어", "하는", "되는",
        "하고", "되고", "한", "할", "함", "됨",
    ]
    private static let koreanParticles = [
        "이라도", "에서", "에게", "으로", "라도", "까지", "부터", "처럼", "마다",
        "이나", "조차", "마저", "밖에", "이며", "은", "는", "이", "가", "을",
        "를", "과", "와", "의", "에", "도", "만", "나", "며", "뿐", "로",
    ].sorted { $0.count > $1.count }

    private static let koreanStopwords: Set<String> = [
        "회의", "내용", "경우", "관련", "사항", "진행", "확인", "검토", "부분",
        "우리", "그것", "이것", "저것", "등", "및", "통해", "위해", "대한",
        "따라", "이번", "해당", "기반", "사용", "작업", "문서", "자료",
        "안건", "정도", "결과", "방식", "오늘", "내일", "현재", "이후",
        "이전", "전체", "각각", "상태", "추가",
    ]

    private static let englishStopwords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "onto", "over", "under",
        "this", "that", "these", "those", "are", "was", "were", "be", "been",
        "being", "have", "has", "had", "not", "but", "or", "of", "in", "on",
        "to", "by", "as", "at", "is", "it", "its", "an", "a", "if",
    ]

    public static func extract(from document: String, existingTerms: [String] = [], limit: Int = defaultLimit) -> [String] {
        guard limit > 0 else { return [] }
        guard !document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let existingKeys = existingComparableKeys(from: existingTerms)
        var candidates: [String: Candidate] = [:]
        collectASCIICandidates(from: document, existingKeys: existingKeys, into: &candidates)
        collectKoreanNounCandidates(from: document, existingKeys: existingKeys, into: &candidates)

        return candidates.values
            .sorted { lhs, rhs in
                if lhs.isHighConfidence != rhs.isHighConfidence {
                    return lhs.isHighConfidence && !rhs.isHighConfidence
                }
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.firstLocation < rhs.firstLocation
            }
            .prefix(limit)
            .map(\.term)
    }

    public static func mergeGlossary(userGlossary: String, document: String, limit: Int = defaultLimit) -> String {
        let existingTerms = glossaryLines(from: userGlossary)
        let extractedTerms = extract(from: document, existingTerms: existingTerms, limit: limit)
        guard !extractedTerms.isEmpty else { return userGlossary }
        let appended = extractedTerms.joined(separator: "\n")
        guard !userGlossary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return appended
        }
        let separator = userGlossary.last?.isNewline == true ? "" : "\n"
        return userGlossary + separator + appended
    }

    private static func collectASCIICandidates(
        from document: String,
        existingKeys: Set<String>,
        into candidates: inout [String: Candidate]
    ) {
        guard let expression = asciiExpression else {
            return
        }

        let fullRange = NSRange(document.startIndex..<document.endIndex, in: document)
        for match in expression.matches(in: document, range: fullRange) {
            guard let range = Range(match.range, in: document) else { continue }
            recordCandidate(
                String(document[range]),
                location: match.range.location,
                existingKeys: existingKeys,
                isHighConfidence: true,
                into: &candidates
            )
        }
    }

    private static func collectKoreanNounCandidates(
        from document: String,
        existingKeys: Set<String>,
        into candidates: inout [String: Candidate]
    ) {
        let tokenizationInput = normalizedKoreanTokenizerInput(from: document)
        let supportsKoreanLexicalClass = NLTagger
            .availableTagSchemes(for: .word, language: .korean)
            .contains(.lexicalClass)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = tokenizationInput

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = tokenizationInput
        tagger.setLanguage(.korean, range: tokenizationInput.startIndex..<tokenizationInput.endIndex)

        tokenizer.enumerateTokens(in: tokenizationInput.startIndex..<tokenizationInput.endIndex) { tokenRange, _ in
            let token = String(tokenizationInput[tokenRange])
            guard containsHangul(token) else { return true }
            let (tag, _) = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lexicalClass)
            guard tag == .noun || !supportsKoreanLexicalClass else { return true }
            guard let stem = normalizedKoreanTerm(token) else { return true }

            let nsRange = NSRange(tokenRange, in: tokenizationInput)
            recordCandidate(
                stem,
                location: nsRange.location,
                existingKeys: existingKeys,
                isHighConfidence: false,
                into: &candidates
            )
            return true
        }
    }

    /// 한국어 토큰화 입력 정규화.
    ///
    /// `NLTokenizer`의 한국어 enumeration은 공백으로 둘러싸인 dash·하이픈 같은 separator를
    /// 만나면 그 지점에서 토큰 열거를 중단해 이후 문서 전체를 누락한다(측정으로 확인).
    /// 그래서 단어문자(한글·영문·숫자·공백류) 외 모든 문자를 공백으로 1:1 치환한다
    /// (길이 보존 → 토큰 NSRange offset·firstLocation 정합 유지).
    /// ASCII 하이픈도 공백화하지만, dry-run·RFC-2616 같은 ASCII 용어는 원본 document를 쓰는
    /// `collectASCIICandidates`(정규식)가 별도 추출하므로 영향이 없다.
    private static func normalizedKoreanTokenizerInput(from document: String) -> String {
        String(String.UnicodeScalarView(document.unicodeScalars.map { scalar in
            isKoreanTokenizerWordScalar(scalar) ? scalar : " "
        }))
    }

    private static func isKoreanTokenizerWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return true
        }
        let value = scalar.value
        return (0xAC00...0xD7A3).contains(value)   // 한글 음절
            || (0x1100...0x11FF).contains(value)   // 한글 자모
            || (0x3130...0x318F).contains(value)   // 한글 호환 자모
            || (0x30...0x39).contains(value)       // 숫자
            || (0x41...0x5A).contains(value)       // A–Z
            || (0x61...0x7A).contains(value)       // a–z
    }

    private static func recordCandidate(
        _ rawTerm: String,
        location: Int,
        existingKeys: Set<String>,
        isHighConfidence: Bool,
        into candidates: inout [String: Candidate]
    ) {
        let term = trimPunctuationAndSymbols(rawTerm)
        guard isLongEnough(term), !isStopword(term) else { return }

        let key = comparableText(term)
        guard !key.isEmpty, !existingKeys.contains(key) else { return }

        if var candidate = candidates[key] {
            candidate.count += 1
            candidate.isHighConfidence = candidate.isHighConfidence || isHighConfidence
            candidates[key] = candidate
        } else {
            candidates[key] = Candidate(
                term: term,
                count: 1,
                firstLocation: location,
                isHighConfidence: isHighConfidence
            )
        }
    }

    private static func normalizedKoreanTerm(_ token: String) -> String? {
        let stem = trimPunctuationAndSymbols(token)
        guard !stem.isEmpty else { return nil }
        guard !isKoreanVerbLike(stem) else { return nil }
        return stripKoreanParticle(from: stem)
    }

    private static func isKoreanVerbLike(_ stem: String) -> Bool {
        for ending in koreanVerbEndings {
            if stem.count > ending.count, stem.hasSuffix(ending) {
                return true
            }
        }
        return stem.count > 1 && stem.hasSuffix("다")
    }

    private static func stripKoreanParticle(from stem: String) -> String {
        for particle in koreanParticles {
            if stem.count > particle.count + 1, stem.hasSuffix(particle) {
                return String(stem.dropLast(particle.count))
            }
        }
        return stem
    }

    static func existingComparableKeys(from terms: [String]) -> Set<String> {
        var keys = Set<String>()
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            insertComparableKey(trimmed, into: &keys)
            insertComparableKey(glossaryTermHead(trimmed), into: &keys)
        }
        return keys
    }

    private static func insertComparableKey(_ term: String, into keys: inout Set<String>) {
        let key = comparableText(term)
        if !key.isEmpty {
            keys.insert(key)
        }
    }

    static func glossaryLines(from glossary: String) -> [String] {
        glossary
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func glossaryTermHead(_ line: String) -> String {
        let separators = ["=", ":", "："]
        var head = line
        for separator in separators {
            if let range = head.range(of: separator) {
                head = String(head[..<range.lowerBound])
            }
        }
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimPunctuationAndSymbols(_ text: String) -> String {
        let trimSet = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        return text.trimmingCharacters(in: trimSet)
    }

    static func comparableText(_ text: String) -> String {
        removePunctuationSymbolsAndWhitespace(text)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: foldLocale
            )
    }

    private static func isLongEnough(_ text: String) -> Bool {
        removePunctuationSymbolsAndWhitespace(text).count >= 2
    }

    private static func isStopword(_ text: String) -> Bool {
        let key = comparableText(text)
        return koreanStopwords.contains(key) || englishStopwords.contains(key)
    }

    static func removePunctuationSymbolsAndWhitespace(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        })
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)
                || (0x1100...0x11FF).contains(scalar.value)
                || (0x3130...0x318F).contains(scalar.value)
        }
    }
}
