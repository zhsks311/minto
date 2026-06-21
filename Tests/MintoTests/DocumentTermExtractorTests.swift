import Testing
@testable import MintoCore

@Suite("DocumentTermExtractor")
struct DocumentTermExtractorTests {

    @Test("ASCII 약어와 기술 토큰을 추출한다")
    func extractsASCIITerms() {
        let terms = DocumentTermExtractor.extract(
            from: "STT 엔진과 VAD를 Liquibase로 dry-run 했다",
            limit: 10
        )

        #expect(terms.contains("STT"))
        #expect(terms.contains("VAD"))
        #expect(terms.contains("Liquibase"))
        #expect(terms.contains("dry-run"))
    }

    @Test("한국어 도메인 용어를 추출하고 흔한 일반어는 제외한다")
    func extractsKoreanTermsAndFiltersStopwords() {
        let terms = DocumentTermExtractor.extract(
            from: "마이그레이션 파이프라인 회의 내용 회의 내용",
            limit: 10
        )

        #expect(terms.contains("마이그레이션"))
        #expect(terms.contains("파이프라인"))
        #expect(!terms.contains("회의"))
        #expect(!terms.contains("내용"))
    }

    @Test("빈도가 높은 용어를 앞에 두고 동률이면 첫 등장 순서를 유지한다")
    func ranksByFrequencyThenFirstAppearance() {
        let terms = DocumentTermExtractor.extract(
            from: "VAD STT Liquibase VAD STT VAD",
            limit: 10
        )

        #expect(Array(terms.prefix(3)) == ["VAD", "STT", "Liquibase"])
    }

    @Test("existingTerms에 있는 용어는 대소문자를 무시하고 제외한다")
    func excludesExistingTermsCaseInsensitively() {
        let terms = DocumentTermExtractor.extract(
            from: "STT VAD STT",
            existingTerms: ["stt"],
            limit: 10
        )

        #expect(!terms.contains("STT"))
        #expect(terms.contains("VAD"))
    }

    @Test("key=value 형식 existingTerms의 head를 대소문자 무시하고 제외한다")
    func excludesExistingTermsHeadCaseInsensitively() {
        let terms = DocumentTermExtractor.extract(
            from: "Liquibase STT",
            existingTerms: ["liquibase = DB migration"],
            limit: 10
        )

        #expect(!terms.contains("Liquibase"))
        #expect(terms.contains("STT"))
    }

    @Test("한국어 조사를 제거하고 같은 stem 빈도를 병합한다")
    func stripsKoreanParticleAndMergesStemFrequency() {
        let terms = DocumentTermExtractor.extract(
            from: "옵션화를 검토하고 옵션화 범위를 정했다",
            limit: 10
        )

        #expect(terms.first == "옵션화")
        #expect(terms.contains("옵션화"))
        #expect(!terms.contains("옵션화를"))
    }

    @Test("한국어 용언 후보를 제외한다")
    func rejectsKoreanVerbLikeCandidates() {
        let terms = DocumentTermExtractor.extract(
            from: "지원한다 변경해야 도입하면 옵션화 정책",
            limit: 10
        )

        #expect(!terms.contains("지원한다"))
        #expect(!terms.contains("변경해야"))
        #expect(!terms.contains("도입하면"))
        #expect(terms.contains("옵션화"))
    }

    @Test("희소 ASCII 고신뢰 용어를 빈도 높은 한국어보다 먼저 포함한다")
    func prioritizesHighConfidenceASCIITerms() {
        let terms = DocumentTermExtractor.extract(
            from: "마이그레이션 마이그레이션 마이그레이션 파이프라인 파이프라인 파이프라인 장바구니 장바구니 Liquibase",
            limit: 5
        )

        #expect(terms.contains("Liquibase"))
    }

    @Test("조사 제거 후 한 글자만 남는 경우 원문을 유지한다")
    func avoidsOverStrippingTwoCharacterKoreanTerms() {
        let terms = DocumentTermExtractor.extract(
            from: "도로 도로 개선",
            limit: 10
        )

        #expect(terms.contains("도로"))
    }

    @Test("limit 값으로 결과 개수를 제한한다")
    func appliesLimit() {
        let terms = DocumentTermExtractor.extract(
            from: "Alpha Beta Gamma Delta Echo",
            limit: 3
        )

        #expect(terms.count <= 3)
    }

    @Test("빈 문서는 빈 결과를 반환한다")
    func failSoftForEmptyDocument() {
        #expect(DocumentTermExtractor.extract(from: " \n\t ").isEmpty)
    }

    @Test("mergeGlossary는 사용자 용어집을 보존하고 문서 용어를 뒤에 추가한다")
    func mergeGlossaryPreservesUserGlossaryAndAppendsTerms() {
        let userGlossary = "STT\nLiquibase = DB migration"
        let merged = DocumentTermExtractor.mergeGlossary(
            userGlossary: userGlossary,
            document: "STT VAD Liquibase dry-run",
            limit: 10
        )
        let lines = merged.split(whereSeparator: { $0.isNewline }).map(String.init)

        #expect(merged.hasPrefix(userGlossary + "\n"))
        #expect(lines.contains("VAD"))
        #expect(lines.contains("dry-run"))
        #expect(lines.filter { $0 == "STT" }.count == 1)
        #expect(!lines.contains("Liquibase"))
    }

    @Test("같은 입력은 같은 순서의 결과를 반환한다")
    func deterministicForSameInput() {
        let document = "STT VAD STT 마이그레이션 파이프라인 VAD"

        let first = DocumentTermExtractor.extract(from: document, limit: 10)
        let second = DocumentTermExtractor.extract(from: document, limit: 10)

        #expect(first == second)
    }
}
