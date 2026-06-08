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
}
