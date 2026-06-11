import Testing
@testable import MintoCore

@Suite("CorrectionAliasExtractor")
struct CorrectionAliasExtractorTests {

    @Test("단순 치환은 교정문을 canonical, 원문을 alias로 추출한다")
    func simpleReplacement() {
        let pairs = CorrectionAliasExtractor.extract(
            raw: "오늘 리퀴베이스 마이그레이션을 봅니다",
            corrected: "오늘 Liquibase 마이그레이션을 봅니다"
        )

        #expect(pairs.count == 1)
        #expect(pairs[0].canonical == "Liquibase")
        #expect(pairs[0].alias == "리퀴베이스")
    }

    @Test("다토큰 영어 분절 alias는 canonical과 접합 동일할 때 추출한다")
    func multiTokenSegmentedAlias() {
        let pairs = CorrectionAliasExtractor.extract(
            raw: "오늘 liqui base 설정을 봅니다",
            corrected: "오늘 Liquibase 설정을 봅니다"
        )

        #expect(pairs.count == 1)
        #expect(pairs[0].canonical == "Liquibase")
        #expect(pairs[0].alias == "liqui base")
    }

    @Test("어순 변경은 별칭으로 추출하지 않는다")
    func ignoresReorderedText() {
        let pairs = CorrectionAliasExtractor.extract(
            raw: "오늘 리퀴베이스 점검",
            corrected: "Liquibase 오늘 점검"
        )

        #expect(pairs.isEmpty)
    }

    @Test("한영 조건과 분절 조건을 모두 만족하지 않으면 무시한다")
    func ignoresUnsupportedScriptPair() {
        let koreanOnly = CorrectionAliasExtractor.extract(
            raw: "오늘 리퀴베이스 점검",
            corrected: "오늘 플라이웨이 점검"
        )
        let unrelatedEnglish = CorrectionAliasExtractor.extract(
            raw: "오늘 fly way 점검",
            corrected: "오늘 Liquibase 점검"
        )

        #expect(koreanOnly.isEmpty)
        #expect(unrelatedEnglish.isEmpty)
    }

    @Test("동일 텍스트는 추출하지 않는다")
    func identicalTextExtractsNothing() {
        let pairs = CorrectionAliasExtractor.extract(
            raw: "오늘 Liquibase 점검",
            corrected: "오늘 Liquibase 점검"
        )

        #expect(pairs.isEmpty)
    }
}
