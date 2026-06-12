import Testing
@testable import MintoCore

/// 배치 교정 프롬프트 빌더 및 응답 파서 단위 테스트.
@Suite("BatchCorrectionPrompt")
struct BatchCorrectionPromptTests {

    // MARK: - 빌더 테스트

    @Test("번호 목록 형식으로 입력이 구성된다")
    func buildProducesNumberedList() {
        let (_, userContent) = BatchCorrectionPrompt.build(
            texts: ["첫 번째 인식", "두 번째 인식", "세 번째 인식"],
            topic: "",
            glossary: "",
            context: ""
        )
        #expect(userContent.contains("[1] 첫 번째 인식"))
        #expect(userContent.contains("[2] 두 번째 인식"))
        #expect(userContent.contains("[3] 세 번째 인식"))
    }

    @Test("instructions에 항목 수와 응답 형식 규칙이 포함된다")
    func instructionsContainCountAndFormatRule() {
        let (instructions, _) = BatchCorrectionPrompt.build(
            texts: ["a", "b"],
            topic: "",
            glossary: "",
            context: ""
        )
        #expect(instructions.contains("2개"))
        #expect(instructions.contains("[1]"))
        #expect(instructions.contains("[2]"))
        #expect(instructions.contains("응답 형식"))
    }

    @Test("회의 맥락이 있으면 userContent에 포함된다")
    func buildIncludesMeetingContext() {
        let (_, userContent) = BatchCorrectionPrompt.build(
            texts: ["텍스트"],
            topic: "분기 실적",
            glossary: "Liquibase\nSTT",
            context: "이전 발화"
        )
        #expect(userContent.contains("분기 실적"))
        #expect(userContent.contains("Liquibase"))
        #expect(userContent.contains("STT"))
        #expect(userContent.contains("이전 발화"))
    }

    @Test("빈 텍스트 목록이면 빈 쌍을 반환한다")
    func buildWithEmptyTextsReturnsEmpty() {
        let (instructions, userContent) = BatchCorrectionPrompt.build(
            texts: [],
            topic: "주제",
            glossary: "용어",
            context: "맥락"
        )
        #expect(instructions.isEmpty)
        #expect(userContent.isEmpty)
    }

    // MARK: - 파서 테스트

    @Test("정상 응답을 파싱하면 교정문 배열을 반환한다")
    func parseValidResponse() {
        let response = """
        [1] 교정된 첫 번째 문장
        [2] 교정된 두 번째 문장
        [3] 교정된 세 번째 문장
        """
        let result = BatchCorrectionPrompt.parse(response: response, expectedCount: 3)
        #expect(result != nil)
        #expect(result?.count == 3)
        #expect(result?[0] == "교정된 첫 번째 문장")
        #expect(result?[1] == "교정된 두 번째 문장")
        #expect(result?[2] == "교정된 세 번째 문장")
    }

    @Test("번호 누락이면 nil을 반환한다")
    func parseMissingNumberReturnsNil() {
        // [2]가 없음
        let response = """
        [1] 첫 번째
        [3] 세 번째
        """
        let result = BatchCorrectionPrompt.parse(response: response, expectedCount: 3)
        #expect(result == nil)
    }

    @Test("세그먼트 수 불일치이면 nil을 반환한다")
    func parseCountMismatchReturnsNil() {
        let response = """
        [1] 첫 번째
        [2] 두 번째
        """
        // expectedCount=3인데 응답은 2개
        let result = BatchCorrectionPrompt.parse(response: response, expectedCount: 3)
        #expect(result == nil)
    }

    @Test("순서 뒤섞임이면 nil을 반환한다")
    func parseOutOfOrderReturnsNil() {
        // [2]가 [1]보다 먼저 등장
        let response = """
        [2] 두 번째
        [1] 첫 번째
        """
        let result = BatchCorrectionPrompt.parse(response: response, expectedCount: 2)
        #expect(result == nil)
    }

    @Test("항목 텍스트가 빈 문자열이면 해당 항목은 nil로 반환된다")
    func parseEmptyItemReturnsNilForThatItem() {
        let response = """
        [1] 교정된 문장
        [2]
        [3] 세 번째 교정
        """
        let result = BatchCorrectionPrompt.parse(response: response, expectedCount: 3)
        #expect(result != nil)
        #expect(result?[0] == "교정된 문장")
        #expect(result?[1] == nil)
        #expect(result?[2] == "세 번째 교정")
    }

    @Test("단일 항목 배치도 정상 파싱된다")
    func parseSingleItem() {
        let response = "[1] 단일 교정 결과"
        let result = BatchCorrectionPrompt.parse(response: response, expectedCount: 1)
        #expect(result?.count == 1)
        #expect(result?[0] == "단일 교정 결과")
    }

    @Test("expectedCount가 0이면 빈 배열을 반환한다")
    func parseZeroExpectedCountReturnsEmpty() {
        let result = BatchCorrectionPrompt.parse(response: "", expectedCount: 0)
        #expect(result?.isEmpty == true)
    }

    @Test("마커 앞뒤 공백이 있어도 파싱된다")
    func parseWithLeadingWhitespace() {
        let response = """
          [1] 들여쓰기 있는 응답
          [2] 두 번째 항목
        """
        let result = BatchCorrectionPrompt.parse(response: response, expectedCount: 2)
        #expect(result != nil)
        #expect(result?[0] == "들여쓰기 있는 응답")
        #expect(result?[1] == "두 번째 항목")
    }

    @Test("빌드 후 모의 응답으로 왕복 파싱이 성공한다")
    func buildAndParseRoundTrip() {
        let texts = ["첫 번째 인식 결과", "두 번째 인식 결과"]
        let (_, _) = BatchCorrectionPrompt.build(
            texts: texts,
            topic: "회의",
            glossary: "",
            context: ""
        )

        // 모의 LLM 응답
        let mockResponse = """
        [1] 첫 번째 교정 결과
        [2] 두 번째 교정 결과
        """
        let parsed = BatchCorrectionPrompt.parse(response: mockResponse, expectedCount: texts.count)
        #expect(parsed?.count == texts.count)
        #expect(parsed?[0] == "첫 번째 교정 결과")
        #expect(parsed?[1] == "두 번째 교정 결과")
    }
}
