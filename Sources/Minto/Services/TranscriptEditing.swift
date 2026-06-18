import Foundation

/// 저장된 전사 segment의 텍스트 편집 draft.
/// 원본 segment의 identity와 시간·화자는 유지하고, 텍스트가 바뀐 segment만 words 매핑을 폐기한다.
struct TranscriptEditDraft: Equatable {
    let recordID: UUID
    let originalSegments: [Segment]
    var draftTexts: [Segment.ID: String]

    init(record: MeetingRecord) {
        self.recordID = record.id
        self.originalSegments = record.transcript
        self.draftTexts = Dictionary(uniqueKeysWithValues: record.transcript.map { ($0.id, $0.text) })
    }

    func text(for segment: Segment) -> String {
        draftTexts[segment.id] ?? segment.text
    }

    mutating func setText(_ text: String, for segmentID: Segment.ID) {
        draftTexts[segmentID] = text
    }

    var editedSegments: [Segment] {
        Self.editedSegments(from: originalSegments, draftTexts: draftTexts)
    }

    var hasChanges: Bool {
        editedSegments != originalSegments
    }

    var changedTextCount: Int {
        originalSegments.reduce(0) { count, segment in
            count + (text(for: segment) == segment.text ? 0 : 1)
        }
    }

    var removedSegmentCount: Int {
        originalSegments.reduce(0) { count, segment in
            let text = text(for: segment)
            return count + (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0)
        }
    }

    static func editedSegments(
        from originalSegments: [Segment],
        draftTexts: [Segment.ID: String]
    ) -> [Segment] {
        originalSegments.compactMap { segment in
            let editedText = draftTexts[segment.id] ?? segment.text
            guard !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            guard editedText != segment.text else {
                return segment
            }
            return Segment(
                id: segment.id,
                text: editedText,
                timestamp: segment.timestamp,
                duration: segment.duration,
                speaker: segment.speaker,
                words: nil
            )
        }
    }
}

enum TranscriptEditing {
    @MainActor
    @discardableResult
    static func save(_ draft: TranscriptEditDraft, in store: MeetingStore) -> MeetingSaveResult {
        guard let current = store.meetings.first(where: { $0.id == draft.recordID }) else {
            return .failed
        }
        var updated = current
        updated.transcript = draft.editedSegments
        return store.save(updated)
    }
}
