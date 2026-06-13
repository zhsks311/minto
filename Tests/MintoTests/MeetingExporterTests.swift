import Testing
@testable import MintoCore
import Foundation

@Suite("MeetingExporter Markdown")
struct MeetingExporterTests {

    private func sample() -> MeetingResult {
        MeetingResult(
            title: "주간 회의",
            metaText: "6월 4일 · 12분 · 구간 2개",
            summary: MeetingSummary(
                title: "주간 회의",
                leadQuestion: "이번 주 핵심?",
                leadAnswer: "핵심 요약 내용",
                sections: [.init(title: "1. 주제", time: "00:10", points: [.init(text: "포인트", subPoints: ["세부"])])],
                keywords: ["kw"],
                decisions: [.init(text: "다음 배포는 금요일에 진행", time: "00:20")],
                actionItems: [.init(task: "체크리스트 정리", owner: "지민", due: "목요일", time: "00:30")],
                openQuestions: [.init(text: "롤백 기준은 추가 확인", time: "00:40")]
            ),
            transcript: [.init(time: "00:00", text: "안녕하세요"), .init(time: "00:10", text: "시작합니다")]
        )
    }

    @Test("markdown: 제목·메타·요약·전사 모두 포함(표준 MD)")
    func markdownIncludesAll() {
        let md = MeetingExporter.markdown(for: sample())
        #expect(md.contains("# 주간 회의"))
        #expect(md.contains("핵심 요약 내용"))
        #expect(md.contains("## 결정사항"))
        #expect(md.contains("다음 배포는 금요일에 진행"))
        #expect(md.contains("## 할 일"))
        #expect(md.contains("체크리스트 정리"))
        #expect(md.contains("## 미해결 질문"))
        #expect(md.contains("롤백 기준은 추가 확인"))
        #expect(md.contains("### 1. 주제"))
        #expect(md.contains("## 전사"))
        #expect(md.contains("**[00:00]** 안녕하세요"))
        #expect(md.contains("**[00:10]** 시작합니다"))
    }

    @Test("markdown: speaker가 있으면 화자 라벨을 추가하고 없으면 기존 포맷을 유지")
    func markdownTranscriptSpeakerBranch() {
        let result = MeetingResult(
            title: "화자 회의",
            metaText: "",
            summary: MeetingSummary(leadAnswer: "요약"),
            transcript: [
                .init(time: "00:00", text: "안녕하세요", speaker: "나*팀"),
                .init(time: "00:10", text: "시작합니다"),
            ]
        )

        let md = MeetingExporter.markdown(for: result)

        #expect(md.contains(#"**[00:00]** **나\*팀:** 안녕하세요"#))
        #expect(md.contains("**[00:10]** 시작합니다"))
    }

    @Test("filename: 불법 문자 제거 + .md 확장자")
    func filenameSanitized() {
        let r = MeetingResult(title: "a/b:c?d", metaText: "", summary: MeetingSummary(leadAnswer: "x"), transcript: [])
        let name = MeetingExporter.filename(for: r)
        #expect(name.hasSuffix(".md"))
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
        #expect(!name.contains("?"))
    }

    @Test("filename: 빈 제목이면 기본값")
    func filenameEmpty() {
        let r = MeetingResult(title: "", metaText: "", summary: MeetingSummary(leadAnswer: "x"), transcript: [])
        #expect(MeetingExporter.filename(for: r) == "회의.md")
    }
}
