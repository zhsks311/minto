import Foundation

/// 회의에서 발견한 용어 후보. 사용자에게 제안만 하며 자동 등록하지 않는다.
public struct GlossaryCandidate: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var term: String
    public var sourceMeetingID: UUID?
    public var suggestedAliases: [String]
    public var suggestedAt: Date

    public init(
        id: UUID = UUID(),
        term: String,
        sourceMeetingID: UUID? = nil,
        suggestedAliases: [String] = [],
        suggestedAt: Date = Date()
    ) {
        self.id = id
        self.term = term
        self.sourceMeetingID = sourceMeetingID
        self.suggestedAliases = suggestedAliases
        self.suggestedAt = suggestedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, term, sourceMeetingID, suggestedAliases, suggestedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        term = try c.decode(String.self, forKey: .term)
        sourceMeetingID = try? c.decode(UUID.self, forKey: .sourceMeetingID)
        suggestedAliases = (try? c.decode([String].self, forKey: .suggestedAliases)) ?? []
        suggestedAt = try c.decode(Date.self, forKey: .suggestedAt)
    }
}

/// 기존 용어에 추가할 별칭 제안. 사용자 승인 전에는 entry.aliases에 반영하지 않는다.
public struct GlossaryAliasSuggestion: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var entryID: UUID
    public var alias: String
    public var suggestedAt: Date

    public init(
        id: UUID = UUID(),
        entryID: UUID,
        alias: String,
        suggestedAt: Date = Date()
    ) {
        self.id = id
        self.entryID = entryID
        self.alias = alias
        self.suggestedAt = suggestedAt
    }
}

/// 앱 전체에서 재사용하는 회의 용어.
public struct GlossaryEntry: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var canonical: String
    public var aliases: [String]
    public var description: String
    public var category: String
    public var tags: [String]
    public var enabled: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        canonical: String,
        aliases: [String] = [],
        description: String = "",
        category: String = "",
        tags: [String] = [],
        enabled: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.canonical = canonical
        self.aliases = aliases
        self.description = description
        self.category = category
        self.tags = tags
        self.enabled = enabled
        self.updatedAt = updatedAt
    }

    public var normalizedCanonical: String {
        canonical.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isUsable: Bool {
        enabled && !normalizedCanonical.isEmpty
    }
}
