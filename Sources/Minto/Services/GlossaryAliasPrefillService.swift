import Foundation

@MainActor
public struct GlossaryAliasPrefillService {
    public static let shared = GlossaryAliasPrefillService()

    private let providerResolver: @MainActor () -> (any LLMTextGenerationProvider)?

    public init(providerResolver: @escaping @MainActor () -> (any LLMTextGenerationProvider)? = {
        // 요약 provider 설정이 "기본 AI 연결을 따름"의 effective text provider를 소유한다.
        LLMSummarySettingsService.shared.selectedTextProvider()
    }) {
        self.providerResolver = providerResolver
    }

    public func suggestAliases(for term: String) async -> [String] {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty, let provider = providerResolver() else { return [] }

        do {
            let response = try await provider.generateText(LLMTextRequest(
                useCase: .correction,
                instructions: Self.instructions,
                userContent: "용어: \(trimmedTerm)",
                maxOutputTokens: 64
            ))
            let aliases = Self.parseAliases(response.text, excluding: trimmedTerm)
            Log.correction.debug("glossary alias prefill completed count=\(aliases.count, privacy: .public) outputChars=\(response.text.count, privacy: .public)")
            return aliases
        } catch {
            Log.correction.debug("glossary alias prefill failed via \(provider.descriptor.id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func parseAliases(_ text: String, excluding term: String) -> [String] {
        let termKey = foldedKey(term)
        let separators = CharacterSet(charactersIn: ",，、;\n")
        var seen = Set<String>()
        var aliases: [String] = []

        for component in text.components(separatedBy: separators) {
            let alias = hangulAlias(from: cleanedAlias(component))
            let key = foldedKey(alias)
            guard !key.isEmpty, key != termKey else { continue }
            guard alias.count >= 2 else { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            aliases.append(alias)
            if aliases.count == 3 { break }
        }

        return aliases
    }

    private static let instructions = """
    한국어 회의 전사에서 특정 용어가 음성 인식으로 잘못 표기될 법한 한글 표기만 제안합니다.
    규칙:
    - 입력으로 받은 용어 하나만 참고합니다.
    - 회의 내용, 전사, 문맥을 추측하지 않습니다.
    - 1~3개만 쉼표로 구분해 출력합니다.
    - 설명, 번호, 따옴표를 쓰지 않습니다.
    """

    private static func cleanedAlias(_ text: String) -> String {
        var alias = text.trimmingCharacters(in: trimSet)
        alias = removeLeadingListMarker(alias)
        return alias.trimmingCharacters(in: trimSet)
    }

    private static func removeLeadingListMarker(_ text: String) -> String {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = remaining.first, first == "-" || first == "*" || first == "•" {
            remaining.removeFirst()
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let digits = remaining.prefix { $0.isNumber }
        if !digits.isEmpty {
            let rest = remaining.dropFirst(digits.count)
            if let marker = rest.first, marker == "." || marker == ")" {
                remaining = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return remaining
    }

    private static func hangulAlias(from text: String) -> String {
        var tokens: [String] = []
        var current = ""

        for scalar in text.unicodeScalars {
            if isHangul(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens.joined(separator: " ")
    }

    private static let trimSet = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

    private static func foldedKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isHangul(_ scalar: UnicodeScalar) -> Bool {
        (0xAC00...0xD7A3).contains(scalar.value)
            || (0x1100...0x11FF).contains(scalar.value)
            || (0x3130...0x318F).contains(scalar.value)
    }
}
