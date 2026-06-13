import Foundation

/// 저장·열람되는 회의 한 건. 전사 + 구조화 요약 + 메타를 담아 JSON으로 영속화한다.
public struct MeetingRecord: Identifiable, Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public let id: UUID
    public var title: String
    public var startedAt: Date
    public var durationSeconds: TimeInterval
    public var topic: String
    public var summary: MeetingSummary
    public var transcript: [Segment]
    /// 보존된 녹음 오디오 파일명(recordings 디렉터리 기준). 화자분리 등 사후 처리 입력.
    /// optional이라 기존 저장 파일은 nil로 로드된다. 보관 기간 경과로 파일이 지워졌을 수 있다.
    public var audioFileName: String?

    public init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        durationSeconds: TimeInterval,
        topic: String = "",
        summary: MeetingSummary = MeetingSummary(),
        transcript: [Segment] = [],
        audioFileName: String? = nil,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.topic = topic
        self.summary = summary
        self.transcript = transcript
        self.audioFileName = audioFileName
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case title
        case startedAt
        case durationSeconds
        case topic
        case summary
        case transcript
        case audioFileName
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
        transcript = try c.decodeIfPresent([Segment].self, forKey: .transcript) ?? []
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName)
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
