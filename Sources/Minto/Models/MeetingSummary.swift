import Foundation

/// 회의 종료 후 표시용 **계층형 구조화 요약**(릴리스/Lilys AI "자세한 리포트" 스타일).
/// LLM이 JSON으로 반환한 것을 파싱한다. LLM이 필드를 빠뜨려도 깨지지 않게 lenient 디코딩.
///
/// 구조: 리드 Q&A(핵심 질문+답변) → 번호 섹션(소제목 + 상대 시점 + 중첩 불릿) → 키워드.
public struct MeetingSummary: Codable, Sendable, Equatable {

    /// 회의를 대표하는 제목.
    public var title: String
    /// 리드 핵심 질문.
    public var leadQuestion: String
    /// 리드 답변(핵심 요약). **굵게** 강조 마크다운 포함 가능.
    public var leadAnswer: String
    /// 번호 매긴 섹션(계층 본문).
    public var sections: [Section]
    /// 핵심 키워드.
    public var keywords: [String]

    public struct Section: Codable, Sendable, Equatable {
        /// "1. 주제" 형태의 섹션 제목.
        public var title: String
        /// 이 섹션이 시작되는 회의 내 상대 시점(MM:SS). 없으면 "".
        public var time: String
        /// 섹션 본문(굵은 카테고리 + 중첩 세부).
        public var points: [Point]

        public init(title: String = "", time: String = "", points: [Point] = []) {
            self.title = title; self.time = time; self.points = points
        }
        private enum CodingKeys: String, CodingKey { case title, time, points }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            title = (try? c.decode(String.self, forKey: .title)) ?? ""
            time = (try? c.decode(String.self, forKey: .time)) ?? ""
            points = (try? c.decode([Point].self, forKey: .points)) ?? []
        }
    }

    public struct Point: Codable, Sendable, Equatable {
        /// 핵심/카테고리 문장. **굵게** 마크다운 포함 가능.
        public var text: String
        /// 중첩 세부 불릿.
        public var subPoints: [String]

        public init(text: String = "", subPoints: [String] = []) {
            self.text = text; self.subPoints = subPoints
        }
        private enum CodingKeys: String, CodingKey { case text, subPoints }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            text = (try? c.decode(String.self, forKey: .text)) ?? ""
            subPoints = (try? c.decode([String].self, forKey: .subPoints)) ?? []
        }
    }

    public init(
        title: String = "",
        leadQuestion: String = "",
        leadAnswer: String = "",
        sections: [Section] = [],
        keywords: [String] = []
    ) {
        self.title = title
        self.leadQuestion = leadQuestion
        self.leadAnswer = leadAnswer
        self.sections = sections
        self.keywords = keywords
    }

    private enum CodingKeys: String, CodingKey { case title, leadQuestion, leadAnswer, sections, keywords }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        leadQuestion = (try? c.decode(String.self, forKey: .leadQuestion)) ?? ""
        leadAnswer = (try? c.decode(String.self, forKey: .leadAnswer)) ?? ""
        sections = (try? c.decode([Section].self, forKey: .sections)) ?? []
        keywords = (try? c.decode([String].self, forKey: .keywords)) ?? []
    }

    /// 표시할 내용이 사실상 없는지.
    public var isEmpty: Bool {
        leadAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sections.isEmpty
    }

    /// 평문만 있을 때(파싱 실패 폴백) 리드 답변에 담아 감싼다.
    public static func plain(_ text: String) -> MeetingSummary {
        MeetingSummary(leadAnswer: text)
    }

    /// 보고서(.md)용 마크다운 렌더.
    public func markdown() -> String {
        var lines: [String] = []
        let q = leadQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = leadAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { lines.append("> \(q)") }
        if !a.isEmpty { lines.append("**\(a)**"); lines.append("") }
        for section in sections {
            let t = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty || !section.points.isEmpty else { continue }
            let timeSuffix = section.time.isEmpty ? "" : " `\(section.time)`"
            lines.append("### \(t)\(timeSuffix)")
            for point in section.points {
                let pt = point.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pt.isEmpty { lines.append("- \(pt)") }
                for sub in point.subPoints {
                    lines.append("  - \(sub)")
                }
            }
            lines.append("")
        }
        if !keywords.isEmpty {
            lines.append("키워드: \(keywords.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
