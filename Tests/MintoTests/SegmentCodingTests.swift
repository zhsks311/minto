import Foundation
import Testing
@testable import MintoCore

@Suite("Segment Codable")
struct SegmentCodingTests {
    @Test("speaker와 words 없는 기존 JSON은 nil로 디코드된다")
    func decodesLegacySegmentWithoutSpeaker() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let json = """
        {
          "id": "\(id.uuidString)",
          "text": "기존 전사",
          "timestamp": 0,
          "duration": 3.5
        }
        """

        let segment = try JSONDecoder().decode(Segment.self, from: Data(json.utf8))

        #expect(segment.id == id)
        #expect(segment.text == "기존 전사")
        #expect(segment.speaker == nil)
        #expect(segment.words == nil)
    }

    @Test("speaker와 words는 Codable 왕복에서 보존된다")
    func roundTripsSpeakerAndWords() throws {
        let segment = Segment(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            text: "화자 포함 전사",
            timestamp: Date(timeIntervalSinceReferenceDate: 12),
            duration: 4,
            speaker: "나",
            words: [
                WordTimestamp(word: "화자", start: 0.0, end: 0.4),
                WordTimestamp(word: "전사", start: 0.5, end: 1.1),
            ]
        )

        let data = try JSONEncoder().encode(segment)
        let restored = try JSONDecoder().decode(Segment.self, from: data)

        #expect(restored == segment)
        #expect(restored.speaker == "나")
        #expect(restored.words == segment.words)
    }
}
