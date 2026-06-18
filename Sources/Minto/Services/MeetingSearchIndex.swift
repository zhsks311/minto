import Foundation

public struct MeetingSearchChunk: Identifiable, Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case title
        case topic
        case summary
        case section
        case decision
        case actionItem
        case openQuestion
        case transcript
        case document
        case keywords

        public var label: String {
            switch self {
            case .title: return "제목"
            case .topic: return "주제"
            case .summary: return "요약"
            case .section: return "회의 내용"
            case .decision: return "결정"
            case .actionItem: return "할 일"
            case .openQuestion: return "질문"
            case .transcript: return "전사"
            case .document: return "회의 자료"
            case .keywords: return "키워드"
            }
        }

        var rankWeight: Double {
            switch self {
            case .title: return 5
            case .topic: return 4
            case .summary: return 3
            case .decision, .actionItem, .openQuestion: return 2.5
            case .section: return 2
            case .keywords: return 1.5
            case .transcript, .document: return 1
            }
        }
    }

    public let id: String
    public let meetingID: UUID
    public let meetingTitle: String
    public let meetingStartedAt: Date
    public let kind: Kind
    public let time: String
    public let text: String
    public let sourcePath: String
    public let checksum: String
    public let chunkingVersion: Int
    public let order: Int

    public init(
        id: String,
        meetingID: UUID,
        meetingTitle: String,
        meetingStartedAt: Date,
        kind: Kind,
        time: String = "",
        text: String,
        sourcePath: String,
        checksum: String,
        chunkingVersion: Int,
        order: Int
    ) {
        self.id = id
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.meetingStartedAt = meetingStartedAt
        self.kind = kind
        self.time = time
        self.text = text
        self.sourcePath = sourcePath
        self.checksum = checksum
        self.chunkingVersion = chunkingVersion
        self.order = order
    }

    public var label: String {
        let trimmedTime = time.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTime.isEmpty ? kind.label : trimmedTime
    }
}

public struct MeetingSearchResult: Identifiable, Sendable, Equatable {
    public let chunk: MeetingSearchChunk
    public let score: Double
    public let matchedTerms: [String]
    public let preview: String

    public var id: String { chunk.id }
    public var meetingID: UUID { chunk.meetingID }
    public var label: String { chunk.label }
}

public struct MeetingSearchIndex: Sendable, Equatable {
    public static let schemaVersion = 1
    // v3: .document chunk에 800자 길이 상한을 추가한다. 빈 줄 없는 대형 문서가 단일 chunk로
    // 검색·답변 문맥을 잠식하지 않도록 기존 사이드카(v2)는 isCompatible 불일치로 자동 무효화·재빌드된다.
    public static let chunkingVersion = 3
    private static let maxDocumentChunkCharacters = 800

    public let chunks: [MeetingSearchChunk]

    public init(records: [MeetingRecord]) {
        self.chunks = records.flatMap(Self.chunks(for:))
    }

    public init(chunks: [MeetingSearchChunk]) {
        self.chunks = chunks
    }

    public static func chunks(for record: MeetingRecord) -> [MeetingSearchChunk] {
        var builder = ChunkBuilder(record: record)
        builder.append(.title, sourcePath: "title", text: record.title)
        builder.append(.topic, sourcePath: "topic", text: record.topic)
        builder.append(
            .summary,
            sourcePath: "summary.lead",
            text: [record.summary.leadQuestion, record.summary.leadAnswer].joined(separator: "\n")
        )
        builder.append(.keywords, sourcePath: "summary.keywords", text: record.summary.keywords.joined(separator: " "))

        for (index, decision) in record.summary.decisions.enumerated() {
            builder.append(.decision, sourcePath: "summary.decisions[\(index)]", time: decision.time, text: decision.text)
        }
        for (index, item) in record.summary.actionItems.enumerated() {
            let text = [item.task, item.owner, item.due]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            builder.append(.actionItem, sourcePath: "summary.actionItems[\(index)]", time: item.time, text: text)
        }
        for (index, question) in record.summary.openQuestions.enumerated() {
            builder.append(.openQuestion, sourcePath: "summary.openQuestions[\(index)]", time: question.time, text: question.text)
        }
        for (index, section) in record.summary.sections.enumerated() {
            builder.append(.section, sourcePath: "summary.sections[\(index)]", time: section.time, text: sectionText(section))
        }
        for (index, segment) in record.transcript.enumerated() {
            builder.append(
                .transcript,
                sourcePath: "transcript[\(index)]",
                time: relativeTime(segment, in: record),
                text: segment.text
            )
        }
        if let document = record.document {
            let documentBlocks = paragraphBlocks(document).flatMap(Self.lengthCappedDocumentBlocks)
            for (index, block) in documentBlocks.enumerated() {
                builder.append(.document, sourcePath: "document[\(index)]", text: block)
            }
        }
        return builder.chunks
    }

    public func search(
        _ query: String,
        limit: Int = 20,
        expandedTokens: [(token: String, weight: Double)] = []
    ) -> [MeetingSearchResult] {
        let normalizedQuery = Self.normalized(query)
        let terms = Self.queryTerms(query)
        guard !normalizedQuery.isEmpty, !terms.isEmpty else { return [] }

        return chunks.compactMap { chunk -> MeetingSearchResult? in
            let normalizedText = Self.normalized(chunk.text)
            let matched = terms.filter { normalizedText.contains($0) }

            // 확장 토큰 매치: 원토큰과 중복되지 않는 토큰만 추가 기여
            let matchedExpanded = expandedTokens.filter { normalizedText.contains($0.token) }

            guard !matched.isEmpty || normalizedText.contains(normalizedQuery) || !matchedExpanded.isEmpty else {
                return nil
            }

            let exactPhraseScore: Double = normalizedText.contains(normalizedQuery) ? 20 : 0
            let termScore = Double(matched.count) * 6
            let coverageScore = Double(matched.count) / Double(max(terms.count, 1)) * 10
            // 확장 토큰 기여: 원토큰 term 점수(6점)에 weight를 곱한 만큼만 추가
            let expandedScore = matchedExpanded.reduce(0.0) { $0 + 6.0 * $1.weight }
            let score = exactPhraseScore + termScore + coverageScore + expandedScore + chunk.kind.rankWeight

            return MeetingSearchResult(
                chunk: chunk,
                score: score,
                matchedTerms: matched,
                preview: Self.preview(chunk.text)
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.chunk.kind.rankWeight != $1.chunk.kind.rankWeight {
                return $0.chunk.kind.rankWeight > $1.chunk.kind.rankWeight
            }
            if $0.chunk.meetingStartedAt != $1.chunk.meetingStartedAt {
                return $0.chunk.meetingStartedAt > $1.chunk.meetingStartedAt
            }
            if $0.chunk.order != $1.chunk.order { return $0.chunk.order < $1.chunk.order }
            return $0.chunk.id < $1.chunk.id
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    static func queryTerms(_ query: String) -> [String] {
        Array(Set(tokenize(query))).sorted()
    }

    static func normalized(_ text: String) -> String {
        tokenize(text).joined(separator: " ")
    }

    /// 텍스트를 검색 토큰으로 분해한다.
    /// 같은 모듈 내 다른 타입(GlossaryQueryExpander 등)에서 공유해 folding 동작을 일치시킨다.
    static func tokenize(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var scalars = String.UnicodeScalarView()
        for scalar in folded.lowercased().unicodeScalars {
            scalars.append(CharacterSet.alphanumerics.contains(scalar) ? scalar : " ")
        }
        return String(scalars)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func preview(_ text: String, maxLength: Int = 180) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxLength else { return normalized }
        return String(normalized.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func sectionText(_ section: MeetingSummary.Section) -> String {
        var parts = [section.title]
        for point in section.points {
            parts.append(point.text)
            parts.append(contentsOf: point.subPoints)
        }
        return parts.joined(separator: "\n")
    }

    private static func relativeTime(_ segment: Segment, in record: MeetingRecord) -> String {
        let offset = max(0, segment.timestamp.timeIntervalSince(record.startedAt))
        let totalSeconds = Int(offset.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func paragraphBlocks(_ text: String) -> [String] {
        var blocks: [String] = []
        var lines: [String] = []

        // CRLF/CR을 LF로 먼저 정규화한다. .newlines로 직접 쪼개면 "\r\n"이 separator 둘로 처리돼
        // ["a", "", "b"]가 되고, 빈 문단으로 오인해 CRLF 문서(Confluence 등)가 줄마다 과분할된다.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !lines.isEmpty {
                    blocks.append(lines.joined(separator: "\n"))
                    lines.removeAll()
                }
            } else {
                lines.append(line)
            }
        }

        if !lines.isEmpty {
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks
    }

    private static func lengthCappedDocumentBlocks(_ block: String) -> [String] {
        guard block.count > maxDocumentChunkCharacters else {
            return [block]
        }

        var blocks: [String] = []
        var remaining = block[...]

        while remaining.count > maxDocumentChunkCharacters {
            let limit = remaining.index(remaining.startIndex, offsetBy: maxDocumentChunkCharacters)
            let split = lastWhitespaceIndex(in: remaining[..<limit]) ?? limit
            let chunk = String(remaining[..<split]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                blocks.append(chunk)
            }

            remaining = remaining[split...]
            while let first = remaining.first, isWhitespace(first) {
                remaining = remaining.dropFirst()
            }
        }

        let tail = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            blocks.append(tail)
        }
        return blocks
    }

    private static func lastWhitespaceIndex(in text: Substring) -> String.Index? {
        var index = text.endIndex
        while index > text.startIndex {
            index = text.index(before: index)
            if isWhitespace(text[index]) {
                return index
            }
        }
        return nil
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.isWhitespace
    }
}

private struct ChunkBuilder {
    private let record: MeetingRecord
    private var order = 0
    private(set) var chunks: [MeetingSearchChunk] = []

    init(record: MeetingRecord) {
        self.record = record
    }

    mutating func append(_ kind: MeetingSearchChunk.Kind, sourcePath: String, time: String = "", text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let checksum = stableChecksum("\(MeetingSearchIndex.chunkingVersion)|\(kind.rawValue)|\(sourcePath)|\(time)|\(cleaned)")
        let id = "\(record.id.uuidString):v\(MeetingSearchIndex.chunkingVersion):\(kind.rawValue):\(sourcePath):\(checksum)"
        chunks.append(
            MeetingSearchChunk(
                id: id,
                meetingID: record.id,
                meetingTitle: record.title,
                meetingStartedAt: record.startedAt,
                kind: kind,
                time: time,
                text: cleaned,
                sourcePath: sourcePath,
                checksum: checksum,
                chunkingVersion: MeetingSearchIndex.chunkingVersion,
                order: order
            )
        )
        order += 1
    }

    private func stableChecksum(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
