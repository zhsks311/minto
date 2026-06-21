import Testing
@testable import MintoCore

@Suite("DocumentContextSelector")
struct DocumentContextSelectorTests {

    @Test("예산 이하 짧은 문서는 그대로 반환한다")
    func returnsShortDocumentUnchanged() {
        let document = "  STT와 VAD 설정을 확인한다.  "

        let excerpt = DocumentContextSelector.excerpt(from: document, maxCharacters: 100)

        #expect(excerpt == document)
    }

    @Test("뒤쪽 용어 밀집 문단을 앞쪽 일반 문단보다 우선 선택한다")
    func prefersTermDenseLaterParagraph() {
        let document = """
        lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor

        OAuth PKCE JWT OAuth PKCE JWT
        """

        let excerpt = DocumentContextSelector.excerpt(from: document, maxCharacters: 32)

        #expect(excerpt.contains("OAuth PKCE JWT"))
        #expect(!excerpt.contains("lorem ipsum"))
    }

    @Test("여러 문단 선택 시 원문 순서를 유지한다")
    func keepsOriginalOrderForSelectedParagraphs() throws {
        let first = "Alpha marker"
        let middle = "OAuth PKCE JWT OAuth PKCE"
        let last = "VAD marker"
        let document = [first, middle, last].joined(separator: "\n\n")

        let excerpt = DocumentContextSelector.excerpt(from: document, maxCharacters: 64)
        let firstRange = try #require(excerpt.range(of: first))
        let middleRange = try #require(excerpt.range(of: middle))

        #expect(firstRange.lowerBound < middleRange.lowerBound)
    }

    @Test("결과는 예산을 넘지 않는다")
    func respectsCharacterBudget() {
        let document = """
        Alpha Beta Gamma Delta Echo Zeta Eta Theta

        OAuth PKCE JWT SAML OIDC GraphQL Kubernetes Terraform Prometheus
        """
        let maxCharacters = 40

        let excerpt = DocumentContextSelector.excerpt(from: document, maxCharacters: maxCharacters)

        #expect(excerpt.count <= maxCharacters)
    }

    @Test("추출 용어가 없으면 기존 prefix 절단과 동일하다")
    func fallsBackToPrefixWhenNoTermsAreExtracted() {
        let document = "lorem ipsum dolor sit amet consectetur adipiscing elit"
        let maxCharacters = 20

        let excerpt = DocumentContextSelector.excerpt(from: document, maxCharacters: maxCharacters)

        #expect(excerpt == String(document.prefix(maxCharacters)))
    }

    @Test("같은 입력은 같은 발췌문을 반환한다")
    func deterministicForSameInput() {
        let document = """
        Alpha Beta Gamma

        OAuth PKCE JWT OAuth

        VAD STT Liquibase dry-run
        """

        let first = DocumentContextSelector.excerpt(from: document, maxCharacters: 72)
        let second = DocumentContextSelector.excerpt(from: document, maxCharacters: 72)

        #expect(first == second)
    }
}
