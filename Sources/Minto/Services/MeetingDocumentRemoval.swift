import Foundation

enum MeetingDocumentRemoval {
    @MainActor
    @discardableResult
    static func removeDocument(recordID: UUID, in store: MeetingStore) -> MeetingSaveResult {
        guard let current = store.meetings.first(where: { $0.id == recordID }) else {
            return .failed
        }
        var updated = current
        updated.document = nil
        return store.save(updated)
    }
}
