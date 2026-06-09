import Foundation

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
