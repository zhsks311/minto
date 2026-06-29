import Foundation

/// 저장·열람되는 회의 한 건. 전사 + 구조화 요약 + 메타를 담아 JSON으로 영속화한다.
public struct MeetingRecord: Identifiable, Codable, Sendable, Equatable {
    public struct MeetingSpeakerEmbedding: Codable, Sendable, Equatable {
        public let speakerLabel: String
        public let embedding: [Float]
        public let embeddingModelID: String
        /// Voiceprint 타입과 인터페이스를 대칭으로 맞춰 VoiceprintMatching의 차원/모델ID 일치 필터가 양쪽에서 동일하게 동작하도록 별도 저장한다.
        public let dimensions: Int

        public init(
            speakerLabel: String,
            embedding: [Float],
            embeddingModelID: String,
            dimensions: Int? = nil
        ) {
            self.speakerLabel = speakerLabel
            self.embedding = embedding
            self.embeddingModelID = embeddingModelID
            self.dimensions = dimensions ?? embedding.count
        }
    }

    public var schemaVersion: Int
    public let id: UUID
    public var title: String
    public var startedAt: Date
    public var durationSeconds: TimeInterval
    public var topic: String
    public var summary: MeetingSummary
    /// 최종 요약 생성에 사용된 resolved glossary 문자열 스냅샷. 빈 값은 저장하지 않는다.
    public var summaryGlossary: String?
    /// 최종 요약에 참고한 회의 자료 스냅샷. 빈 값은 저장하지 않는다.
    /// summaryGlossary와 같은 additive optional 필드라 schemaVersion은 1을 유지한다:
    /// 구 파일은 nil로 로드되고, 키가 있으나 손상된 값은 decodeIfPresent가 throw해 quarantine된다.
    public var document: String?
    /// 매칭된 캘린더 이벤트 식별자. optional이라 기존 저장 파일은 nil로 로드된다.
    public var calendarEventIdentifier: String?
    public var transcript: [Segment]
    /// 보존된 녹음 오디오 파일명(recordings 디렉터리 기준). 화자분리 등 사후 처리 입력.
    /// optional이라 기존 저장 파일은 nil로 로드된다. 보관 기간 경과로 파일이 지워졌을 수 있다.
    public var audioFileName: String?
    /// transcript의 "화자 N" 라벨별 대표 임베딩. 등록/식별의 입력으로 쓰는 L2 정규화 centroid.
    /// optional이라 기존 저장 파일은 nil로 로드된다. 추가 optional 필드라 schemaVersion은 1을 유지한다.
    public var speakerEmbeddings: [MeetingSpeakerEmbedding]?

    public init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        durationSeconds: TimeInterval,
        topic: String = "",
        summary: MeetingSummary = MeetingSummary(),
        summaryGlossary: String? = nil,
        document: String? = nil,
        calendarEventIdentifier: String? = nil,
        transcript: [Segment] = [],
        audioFileName: String? = nil,
        speakerEmbeddings: [MeetingSpeakerEmbedding]? = nil,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.topic = topic
        self.summary = summary
        self.summaryGlossary = Self.normalizedSummaryGlossary(summaryGlossary)
        self.document = Self.normalizedDocument(document)
        self.calendarEventIdentifier = Self.normalizedCalendarEventIdentifier(calendarEventIdentifier)
        self.transcript = transcript
        self.audioFileName = audioFileName
        self.speakerEmbeddings = speakerEmbeddings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case title
        case startedAt
        case durationSeconds
        case topic
        case summary
        case summaryGlossary
        case document
        case calendarEventIdentifier
        case transcript
        case audioFileName
        case speakerEmbeddings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 필수 메타(id/title/startedAt)는 strict — 없거나 깨지면 throw → reload가 quarantine 처리.
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        // 나머지는 키 누락(구 스키마)만 기본값 허용한다. 키가 있는데 내부가 손상된 경우는
        // decodeIfPresent가 throw하므로 부분 데이터를 조용히 기본값으로 덮지 않고 quarantine된다.
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        durationSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .durationSeconds) ?? 0
        topic = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
        summary = try c.decodeIfPresent(MeetingSummary.self, forKey: .summary) ?? MeetingSummary()
        summaryGlossary = Self.normalizedSummaryGlossary(
            try c.decodeIfPresent(String.self, forKey: .summaryGlossary)
        )
        document = Self.normalizedDocument(
            try c.decodeIfPresent(String.self, forKey: .document)
        )
        calendarEventIdentifier = Self.normalizedCalendarEventIdentifier(
            try c.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
        )
        transcript = try c.decodeIfPresent([Segment].self, forKey: .transcript) ?? []
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName)
        speakerEmbeddings = try c.decodeIfPresent([MeetingSpeakerEmbedding].self, forKey: .speakerEmbeddings)
    }

    static func normalizedSummaryGlossary(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedDocument(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedCalendarEventIdentifier(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 비어있는 회의(전사·요약 모두 없음)인지 — 저장 가치 판단용.
    public var isEmpty: Bool {
        transcript.isEmpty && summary.isEmpty
    }

    /// 목록 부제: "6월 4일 · 12분 · 구간 14개".
    public var subtitle: String {
        let f = DateformatterCache.listDate
        let dur = Self.durationText(durationSeconds)
        return "\(f.string(from: startedAt)) · \(dur) · 구간 \(transcript.count)개"
    }

    public static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60, s = total % 60
        return m > 0 ? "\(m)분 \(s)초" : "\(s)초"
    }
}

/// DateFormatter는 생성 비용이 커서 캐시한다.
enum DateformatterCache {
    static let listDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 a h:mm"
        return f
    }()
}
