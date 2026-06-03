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
                keywords: ["kw"]
            ),
            transcript: [.init(time: "00:00", text: "안녕하세요"), .init(time: "00:10", text: "시작합니다")]
        )
    }

    @Test("markdown: 제목·메타·요약·전사 모두 포함(표준 MD)")
    func markdownIncludesAll() {
        let md = MeetingExporter.markdown(for: sample())
        #expect(md.contains("# 주간 회의"))
        #expect(md.contains("핵심 요약 내용"))
        #expect(md.contains("### 1. 주제"))
        #expect(md.contains("## 전사"))
        #expect(md.contains("**[00:00]** 안녕하세요"))
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
