import Testing
@testable import MintoCore
import Foundation

/// SummaryPrompt 순수 빌더 단위 테스트 (네트워크 불필요, CI에서 실행).
@Suite("SummaryPrompt 빌더")
struct SummaryPromptTests {

    @Test("instructions는 고정 요약 정책 + anti-날조, 회의 맥락은 instructions에 없다")
    func instructionsAreFixedPolicy() {
        let p = SummaryPrompt.buildIncremental(
            topic: "행정안전위원회",
            glossary: "행정안전부",
            runningSummary: "",
            newBatch: "회의를 개회합니다."
        )
        #expect(p.instructions.contains("요약하는 전문가"))
        // 날조 방지 핵심 구절
        #expect(p.instructions.contains("날조 금지") || p.instructions.contains("추측해 채우지"))
        // 회의 주제/용어집은 정책(instructions)이 아니라 데이터(userContent)에만
        #expect(!p.instructions.contains("행정안전위원회"))
        #expect(!p.instructions.contains("행정안전부"))
    }

    @Test("incremental: runningSummary가 비면 초기 생성 안내, newBatch는 항상 userContent에")
    func incrementalEmptySummary() {
        let p = SummaryPrompt.buildIncremental(
            topic: "",
            glossary: "",
            runningSummary: "",
            newBatch: "예산안을 심사했습니다."
        )
        #expect(p.userContent.contains("아직 없음"))
        #expect(p.userContent.contains("예산안을 심사했습니다."))
        // 맥락이 비면 회의 블록 없음
        #expect(!p.userContent.contains("참고용 회의 맥락"))
    }

    @Test("incremental: 기존 요약이 있으면 userContent에 포함된다")
    func incrementalWithSummary() {
        let p = SummaryPrompt.buildIncremental(
            topic: "",
            glossary: "",
            runningSummary: "1. 개회 선언",
            newBatch: "2. 안건 상정"
        )
        #expect(p.userContent.contains("1. 개회 선언"))
        #expect(p.userContent.contains("2. 안건 상정"))
        #expect(!p.userContent.contains("아직 없음"))
    }

    @Test("incremental: 참고 문서는 userContent에만 들어가고 instructions에는 없다")
    func incrementalDocumentContext() {
        let p = SummaryPrompt.buildIncremental(
            topic: "",
            glossary: "",
            runningSummary: "",
            newBatch: "검색 고도화 논의를 시작했습니다.",
            document: "[Confluence 참고 문서]\n동의어와 도메인 용어를 검색 문맥에 반영한다."
        )
        #expect(p.userContent.contains("참고 문서(회의 자료)"))
        #expect(p.userContent.contains("동의어와 도메인 용어"))
        #expect(!p.instructions.contains("동의어와 도메인 용어"))
    }

    @Test("final: 전사가 userContent에, 계층 JSON 스키마 + anti-날조 지시")
    func finalTranscriptAndSchema() {
        let p = SummaryPrompt.buildFinal(
            topic: "",
            glossary: "",
            transcript: "[00:00] 안녕하세요 회의를 시작합니다"
        )
        #expect(p.userContent.contains("[00:00] 안녕하세요 회의를 시작합니다"))
        #expect(p.instructions.contains("JSON"))
        #expect(p.instructions.contains("sections"))
        #expect(p.instructions.contains("leadAnswer"))
        #expect(p.instructions.contains("decisions"))
        #expect(p.instructions.contains("actionItems"))
        #expect(p.instructions.contains("openQuestions"))
        #expect(p.instructions.contains("날조 금지"))
    }

    @Test("주제·용어집이 있으면 userContent의 회의 맥락 블록에 들어간다")
    func meetingContextInUserContent() {
        let p = SummaryPrompt.buildFinal(
            topic: "쿠팡 청문회",
            glossary: "불출석 사유서\n상임위",
            transcript: "[00:05] 마지막 발언"
        )
        #expect(p.userContent.contains("참고용 회의 맥락"))
        #expect(p.userContent.contains("쿠팡 청문회"))
        #expect(p.userContent.contains("불출석 사유서"))
        #expect(p.userContent.contains("상임위"))
        #expect(p.userContent.contains("마지막 발언"))
    }

    // MARK: - Phase 6: 문서 요약본 폴백 사슬 (요약본 → excerpt → 없음)

    @Test("incremental: 문서 요약본이 있으면 요약본을 주입하고 excerpt(원문)는 쓰지 않는다")
    func incrementalUsesDocumentSummaryOverExcerpt() {
        let p = SummaryPrompt.buildIncremental(
            topic: "",
            glossary: "",
            runningSummary: "",
            newBatch: "본문",
            document: "원문 본문 전체 — 발췌되면 안 되는 긴 원문 텍스트",
            documentSummary: "- 핵심 안건: 전략수출금융지원법안\n- 진술인 3인"
        )
        #expect(p.userContent.contains("참고 문서 요약"))
        #expect(p.userContent.contains("전략수출금융지원법안"))
        // 요약본이 있으면 raw 원문 발췌 블록은 나오지 않는다.
        #expect(!p.userContent.contains("참고 문서(회의 자료)"))
        #expect(!p.userContent.contains("발췌되면 안 되는"))
    }

    @Test("incremental: 요약본이 비면 document에서 excerpt 폴백")
    func incrementalFallsBackToExcerpt() {
        let p = SummaryPrompt.buildIncremental(
            topic: "",
            glossary: "",
            runningSummary: "",
            newBatch: "본문",
            document: "동의어와 도메인 용어를 검색 문맥에 반영한다.",
            documentSummary: ""
        )
        #expect(p.userContent.contains("참고 문서(회의 자료)"))
        #expect(p.userContent.contains("동의어와 도메인 용어"))
        #expect(!p.userContent.contains("참고 문서 요약"))
    }

    @Test("incremental: document·요약본 모두 비면 문서 블록 없음")
    func incrementalNoDocumentBlock() {
        let p = SummaryPrompt.buildIncremental(
            topic: "",
            glossary: "",
            runningSummary: "",
            newBatch: "본문",
            document: "",
            documentSummary: ""
        )
        #expect(!p.userContent.contains("참고 문서"))
    }

    @Test("final: 문서 요약본이 있으면 요약본을 주입하고 excerpt는 쓰지 않는다")
    func finalUsesDocumentSummaryOverExcerpt() {
        let p = SummaryPrompt.buildFinal(
            topic: "",
            glossary: "",
            transcript: "[00:00] 시작",
            document: "원문 본문 전체 — 발췌되면 안 되는 긴 원문",
            documentSummary: "- 핵심 안건: 공청회"
        )
        #expect(p.userContent.contains("참고 문서 요약"))
        #expect(p.userContent.contains("공청회"))
        #expect(!p.userContent.contains("참고 문서(회의 자료)"))
        #expect(!p.userContent.contains("발췌되면 안 되는"))
    }
}

/// DocumentSummaryPrompt 순수 빌더 단위 테스트.
@Suite("DocumentSummaryPrompt 빌더")
struct DocumentSummaryPromptTests {

    @Test("문서가 있으면 instructions(요약 정책)와 userContent(문서)를 반환한다")
    func buildsPrompt() {
        let p = DocumentSummaryPrompt.build(document: "전략수출금융지원법안 공청회 안건")
        #expect(p.instructions.contains("참고 맥락"))
        #expect(p.instructions.contains("날조 금지"))
        #expect(p.userContent.contains("전략수출금융지원법안 공청회 안건"))
    }

    @Test("빈 문서는 빈 쌍을 반환한다")
    func emptyDocumentReturnsEmpty() {
        let p = DocumentSummaryPrompt.build(document: "   \n  ")
        #expect(p.instructions.isEmpty)
        #expect(p.userContent.isEmpty)
    }

    @Test("문서가 상한을 넘으면 뒷부분을 생략하고 표시한다")
    func capsLongDocument() {
        let long = String(repeating: "가", count: DocumentSummaryPrompt.maxDocumentCharacters + 500)
        let p = DocumentSummaryPrompt.build(document: long)
        #expect(p.userContent.contains("이후 문서 생략"))
        #expect(p.userContent.count < long.count + 100)
    }
}
