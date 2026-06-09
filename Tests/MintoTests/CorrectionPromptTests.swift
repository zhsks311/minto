import Testing
@testable import MintoCore

/// 교정 프롬프트 빌더 순수 단위 테스트 (네트워크·로그인 불필요, CI 실행).
@Suite("CorrectionPrompt 빌더")
struct CorrectionPromptTests {

    @Test("instructions는 고정 정책만, 회의 맥락은 instructions에 없다")
    func instructionsAreFixedPolicyOnly() {
        let p = CorrectionPrompt.build(
            topic: "쿠팡 청문회",
            glossary: "쿠팡",
            context: "이전 발화",
            text: "현재 발화"
        )
        // 사용자 입력(주제/용어집)은 정책 권한(instructions)으로 올라가지 않는다
        #expect(!p.instructions.contains("쿠팡 청문회"))
        #expect(!p.instructions.contains("[참고용 회의 맥락"))
        // 고정 정책은 항상 존재
        #expect(p.instructions.contains("교정 원칙"))
    }

    @Test("instructions는 용어집 exact spelling 보존 규칙을 포함한다")
    func instructionsPreserveGlossaryExactSpelling() {
        let p = CorrectionPrompt.build(topic: "", glossary: "", context: "", text: "리퀴 베이스")

        #expect(p.instructions.contains("exact spelling"))
        #expect(p.instructions.contains("리퀴 베이스"))
        #expect(p.instructions.contains("Liquibase"))
        #expect(p.instructions.contains("dry-run"))
    }

    @Test("빈 회의 맥락이면 userContent에 회의 블록이 없다")
    func emptyMeetingContext() {
        let p = CorrectionPrompt.build(topic: "", glossary: "", context: "이전 발화", text: "현재 발화")
        #expect(!p.userContent.contains("[참고용 회의 맥락"))
        #expect(!p.userContent.contains("회의 주제:"))
        #expect(p.userContent.contains("현재 발화"))
        #expect(p.userContent.contains("이전 발화"))
    }

    @Test("주제·용어집이 있으면 userContent에 포함된다")
    func withMeetingContext() {
        let p = CorrectionPrompt.build(
            topic: "쿠팡 청문회 경제 뉴스",
            glossary: "쿠팡\n상임위\n고란",
            context: "",
            text: "현재 발화"
        )
        #expect(p.userContent.contains("[참고용 회의 맥락"))
        #expect(p.userContent.contains("쿠팡 청문회 경제 뉴스"))
        #expect(p.userContent.contains("쿠팡"))
        #expect(p.userContent.contains("상임위"))
        #expect(p.userContent.contains("고란"))
    }

    @Test("용어집 빈 줄·공백은 제거된다")
    func glossaryTrimsBlankLines() {
        let p = CorrectionPrompt.build(topic: "", glossary: "  네이버  \n\n   \n카카오", context: "", text: "x")
        #expect(p.userContent.contains("네이버, 카카오"))
    }

    @Test("주제만 있어도 회의 블록이 생성되고 용어집 줄은 없다")
    func topicOnly() {
        let p = CorrectionPrompt.build(topic: "분기 실적 리뷰", glossary: "   ", context: "", text: "x")
        #expect(p.userContent.contains("회의 주제: 분기 실적 리뷰"))
        #expect(!p.userContent.contains("용어집(정확한 표기)"))
    }

    @Test("교정 대상 텍스트는 항상 userContent에 들어간다")
    func textAlwaysInUserContent() {
        let p = CorrectionPrompt.build(topic: "주제", glossary: "용어", context: "맥락", text: "교정할문장")
        #expect(p.userContent.contains("교정할문장"))
    }

    @Test("postprocessor는 출력 마커 뒤의 교정문만 남긴다")
    func postprocessorExtractsOutputMarkerText() {
        let raw = """
        오늘 PDCR-2901 마이그레이션에서 리퀴 베이스 → Liquibase로 교정합니다.

        출력: 오늘 PDCR-2901 마이그레이션에서 Liquibase 순서를 확인했습니다.
        """

        #expect(CorrectionOutputPostprocessor.clean(raw) == "오늘 PDCR-2901 마이그레이션에서 Liquibase 순서를 확인했습니다.")
    }

    @Test("postprocessor는 명확한 마커가 없으면 응답을 보존한다")
    func postprocessorPreservesUnmarkedOutput() {
        let raw = """
        첫 번째 교정 문장입니다.
        두 번째 교정 문장입니다.
        """

        #expect(CorrectionOutputPostprocessor.clean(raw) == "첫 번째 교정 문장입니다.\n두 번째 교정 문장입니다.")
        #expect(CorrectionOutputPostprocessor.clean("실험 결과: 배포를 보류했습니다.") == "실험 결과: 배포를 보류했습니다.")
    }

    @Test("postprocessor는 교정문을 감싼 따옴표만 제거한다")
    func postprocessorStripsWrappingQuotes() {
        #expect(CorrectionOutputPostprocessor.clean("  \"교정된 문장\"  ") == "교정된 문장")
        #expect(CorrectionOutputPostprocessor.clean("교정 결과: “교정된 문장”") == "교정된 문장")
    }
}
