import Foundation

/// 회의 종료 후 표시용 **계층형 구조화 요약**(릴리스/Lilys AI "자세한 리포트" 스타일).
/// LLM이 JSON으로 반환한 것을 파싱한다. LLM이 필드를 빠뜨려도 깨지지 않게 lenient 디코딩.
///
/// 구조: 리드 Q&A(핵심 질문+답변) → 결정/할 일/질문 → 번호 섹션(소제목 + 상대 시점 + 중첩 불릿) → 키워드.
public struct MeetingSummary: Codable, Sendable, Equatable {

    /// 회의를 대표하는 제목.
    public var title: String
    /// 리드 핵심 질문.
    public var leadQuestion: String
    /// 리드 답변(핵심 요약). **굵게** 강조 마크다운 포함 가능.
    public var leadAnswer: String
    /// 명시적으로 결정된 내용.
    public var decisions: [Decision]
    /// 후속 작업.
    public var actionItems: [ActionItem]
    /// 아직 답하지 못한 질문.
    public var openQuestions: [OpenQuestion]
    /// 번호 매긴 섹션(계층 본문).
    public var sections: [Section]
    /// 핵심 키워드.
    public var keywords: [String]

    public struct Decision: Codable, Sendable, Equatable {
        public var text: String
        public var time: String

        public init(text: String = "", time: String = "") {
            self.text = text; self.time = time
        }
        private enum CodingKeys: String, CodingKey { case text, time }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            text = (try? c.decode(String.self, forKey: .text)) ?? ""
            time = (try? c.decode(String.self, forKey: .time)) ?? ""
        }
    }

    public struct ActionItem: Codable, Sendable, Equatable {
        public var task: String
        public var owner: String
        public var due: String
        public var time: String
        public var isDone: Bool

        public init(task: String = "", owner: String = "", due: String = "", time: String = "", isDone: Bool = false) {
            self.task = task; self.owner = owner; self.due = due; self.time = time
            self.isDone = isDone
        }
        private enum CodingKeys: String, CodingKey { case task, owner, due, time, isDone }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            task = (try? c.decode(String.self, forKey: .task)) ?? ""
            owner = (try? c.decode(String.self, forKey: .owner)) ?? ""
            due = (try? c.decode(String.self, forKey: .due)) ?? ""
            time = (try? c.decode(String.self, forKey: .time)) ?? ""
            isDone = (try? c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        }
    }

    public struct OpenQuestion: Codable, Sendable, Equatable {
        public var text: String
        public var time: String

        public init(text: String = "", time: String = "") {
            self.text = text; self.time = time
        }
        private enum CodingKeys: String, CodingKey { case text, time }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            text = (try? c.decode(String.self, forKey: .text)) ?? ""
            time = (try? c.decode(String.self, forKey: .time)) ?? ""
        }
    }

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
        keywords: [String] = [],
        decisions: [Decision] = [],
        actionItems: [ActionItem] = [],
        openQuestions: [OpenQuestion] = []
    ) {
        self.title = title
        self.leadQuestion = leadQuestion
        self.leadAnswer = leadAnswer
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
        self.sections = sections
        self.keywords = keywords
    }

    private enum CodingKeys: String, CodingKey {
        case title, leadQuestion, leadAnswer, decisions, actionItems, openQuestions, sections, keywords
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        leadQuestion = (try? c.decode(String.self, forKey: .leadQuestion)) ?? ""
        leadAnswer = (try? c.decode(String.self, forKey: .leadAnswer)) ?? ""
        decisions = (try? c.decode([Decision].self, forKey: .decisions)) ?? []
        actionItems = (try? c.decode([ActionItem].self, forKey: .actionItems)) ?? []
        openQuestions = (try? c.decode([OpenQuestion].self, forKey: .openQuestions)) ?? []
        sections = (try? c.decode([Section].self, forKey: .sections)) ?? []
        keywords = (try? c.decode([String].self, forKey: .keywords)) ?? []
    }

    /// 표시할 내용이 사실상 없는지.
    public var isEmpty: Bool {
        leadAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && decisions.isEmpty
            && actionItems.isEmpty
            && openQuestions.isEmpty
            && sections.isEmpty
    }

    /// 평문만 있을 때(파싱 실패 폴백) 리드 답변에 담아 감싼다.
    public static func plain(_ text: String) -> MeetingSummary {
        MeetingSummary(leadAnswer: text)
    }

    /// `plain(_:)` 폴백 형태인지 — leadAnswer만 있고 구조화 필드(title/leadQuestion/sections/
    /// decisions/actionItems/openQuestions/keywords)가 전부 비어 있는 상태.
    /// 정상 요약이 우연히 이 형태일 가능성은 수용한다(재요약 버튼이 노출돼도 무해).
    public var isPlainFallback: Bool {
        !leadAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && leadQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sections.isEmpty
            && decisions.isEmpty
            && actionItems.isEmpty
            && openQuestions.isEmpty
            && keywords.isEmpty
    }

    /// 보고서(.md)용 마크다운 렌더.
    public func markdown() -> String {
        var lines: [String] = []
        let q = leadQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = leadAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { lines.append("> \(q)") }
        if !a.isEmpty {
            // 다단(개행 포함) 텍스트를 **…**로 감싸면 CommonMark에서 강조가 안 되고 별표 리터럴이 노출된다
            // (평문 폴백 경로). 단일 줄일 때만 bold.
            lines.append(a.contains("\n") ? a : "**\(a)**")
            lines.append("")
        }
        let outcomeMd = outcomesMarkdown()
        if !outcomeMd.isEmpty {
            lines.append(outcomeMd)
            lines.append("")
        }
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

    public func outcomesMarkdown() -> String {
        var groups: [String] = []
        let decisionLines = decisions.compactMap { decisionLine($0) }
        if !decisionLines.isEmpty {
            groups.append((["## 결정사항"] + decisionLines).joined(separator: "\n"))
        }

        let actionLines = actionItems.compactMap { actionLine($0) }
        if !actionLines.isEmpty {
            groups.append((["## 할 일"] + actionLines).joined(separator: "\n"))
        }

        let questionLines = openQuestions.compactMap { questionLine($0) }
        if !questionLines.isEmpty {
            groups.append((["## 미해결 질문"] + questionLines).joined(separator: "\n"))
        }
        return groups.joined(separator: "\n\n")
    }

    public func decisionsMarkdown() -> String {
        let lines = decisions.compactMap { decisionLine($0) }
        return lines.isEmpty ? "" : (["## 결정사항"] + lines).joined(separator: "\n")
    }

    public func actionItemsMarkdown() -> String {
        let lines = actionItems.compactMap { actionLine($0) }
        return lines.isEmpty ? "" : (["## 할 일"] + lines).joined(separator: "\n")
    }

    public func openQuestionsMarkdown() -> String {
        let lines = openQuestions.compactMap { questionLine($0) }
        return lines.isEmpty ? "" : (["## 미해결 질문"] + lines).joined(separator: "\n")
    }

    private func decisionLine(_ decision: Decision) -> String? {
        let text = decision.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return "- \(timePrefix(decision.time))\(text)"
    }

    private func actionLine(_ item: ActionItem) -> String? {
        let task = item.task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return nil }

        let owner = item.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = item.due.trimmingCharacters(in: .whitespacesAndNewlines)
        var meta: [String] = []
        if !owner.isEmpty { meta.append("담당: \(owner)") }
        if !due.isEmpty { meta.append("기한: \(due)") }

        let suffix = meta.isEmpty ? "" : " _(\(meta.joined(separator: " · ")))_"
        let checkbox = item.isDone ? "[x]" : "[ ]"
        return "- \(checkbox) \(timePrefix(item.time))\(task)\(suffix)"
    }

    private func questionLine(_ question: OpenQuestion) -> String? {
        let text = question.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return "- \(timePrefix(question.time))\(text)"
    }

    private func timePrefix(_ time: String) -> String {
        let trimmed = time.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "`\(trimmed)` "
    }
}
