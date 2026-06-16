import Foundation

public struct Voiceprint: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var displayName: String
    public let embedding: [Float]
    public let embeddingModelID: String
    public let dimensions: Int
    public let enrolledAt: Date
    public let sampleCount: Int

    public init(
        id: UUID = UUID(),
        displayName: String,
        embedding: [Float],
        embeddingModelID: String,
        enrolledAt: Date = Date(),
        sampleCount: Int = 1
    ) {
        self.id = id
        self.displayName = displayName
        self.embedding = embedding
        self.embeddingModelID = embeddingModelID
        self.dimensions = embedding.count
        self.enrolledAt = enrolledAt
        self.sampleCount = sampleCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, embedding, embeddingModelID, dimensions, enrolledAt, sampleCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        embedding = try c.decode([Float].self, forKey: .embedding)
        embeddingModelID = try c.decode(String.self, forKey: .embeddingModelID)
        dimensions = try c.decode(Int.self, forKey: .dimensions)
        enrolledAt = try c.decode(Date.self, forKey: .enrolledAt)
        sampleCount = try c.decode(Int.self, forKey: .sampleCount)

        guard dimensions == embedding.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .dimensions,
                in: c,
                debugDescription: "dimensions must match embedding.count"
            )
        }
    }
}
