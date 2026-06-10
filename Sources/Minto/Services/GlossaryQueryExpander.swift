import Foundation

/// 용어집(GlossaryEntry 배열)을 활용해 쿼리 토큰을 확장한다.
/// 예: 쿼리 토큰 "리퀴베이스" → 용어집에 "Liquibase = 리퀴베이스" 등록 시
///     "liquibase" 토큰을 weight 0.8로 추가 반환.
///
/// 순수 함수 구조 (GlossaryStore 인스턴스를 직접 참조하지 않음) — 테스트 용이.
public struct GlossaryQueryExpander: Sendable {

    /// 확장 토큰 가중치. 원토큰 직접 매치보다 항상 낮아야 한다.
    public static let expansionWeight: Double = 0.8

    /// 쿼리 토큰을 용어집으로 확장한다.
    ///
    /// - Parameters:
    ///   - queryTokens: `MeetingSearchIndex.queryTerms(_:)` 로 얻은 토큰 목록
    ///   - entries: 용어집 항목. 호출측에서 `isUsable` 필터 적용 후 전달
    /// - Returns: 확장 토큰과 가중치 쌍. 원 queryTokens와 중복되지 않는 항목만 포함
    public static func expand(
        queryTokens: [String],
        entries: [GlossaryEntry]
    ) -> [(token: String, weight: Double)] {
        guard !queryTokens.isEmpty, !entries.isEmpty else { return [] }

        let foldingOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        let foldedQueryTokens = queryTokens.map { $0.folding(options: foldingOptions, locale: .current) }
        let queryTokenSet = Set(foldedQueryTokens)

        var expandedTokens: [(token: String, weight: Double)] = []
        var seenTokens = queryTokenSet

        for entry in entries {
            // 이 entry의 모든 표기(canonical + aliases)를 모은다
            var allSurfaces: [String] = [entry.canonical]
            allSurfaces.append(contentsOf: entry.aliases)

            // 쿼리 토큰 중 이 entry의 표기 중 하나라도 일치하는 것이 있는지 확인
            let entryMatches = allSurfaces.contains { surface in
                let surfaceTokens = tokenize(surface)
                return surfaceTokens.contains { surfaceToken in
                    foldedQueryTokens.contains { queryToken in
                        queryToken == surfaceToken
                    }
                }
            }
            guard entryMatches else { continue }

            // 일치한 entry의 나머지 표기에서 확장 토큰을 수집
            for surface in allSurfaces {
                for token in tokenize(surface) {
                    guard !seenTokens.contains(token) else { continue }
                    seenTokens.insert(token)
                    expandedTokens.append((token: token, weight: Self.expansionWeight))
                }
            }
        }

        return expandedTokens
    }

    /// MeetingSearchIndex.tokenize 와 동일한 로직.
    /// 두 곳에서 독립적으로 유지해 MeetingSearchIndex 내부에 의존하지 않는다.
    private static func tokenize(_ text: String) -> [String] {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var scalars = String.UnicodeScalarView()
        for scalar in folded.lowercased().unicodeScalars {
            scalars.append(CharacterSet.alphanumerics.contains(scalar) ? scalar : " ")
        }
        return String(scalars)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
