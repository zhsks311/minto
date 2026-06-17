import os
import Foundation
import Combine

@MainActor
public final class VoiceprintStore: ObservableObject {
    public static let shared = VoiceprintStore()
    public static let schemaVersion = 1

    @Published public private(set) var voiceprints: [Voiceprint] = []

    private let dir: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter directory: 저장 디렉터리. nil이면 ~/Library/Application Support/Minto/voiceprints.
    public init(directory: URL? = nil) {
        if let directory {
            dir = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            dir = base.appendingPathComponent("Minto/voiceprints", isDirectory: true)
        }
        fileURL = dir.appendingPathComponent("voiceprints.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        encoder = MeetingRecordCoding.makeEncoder()
        decoder = MeetingRecordCoding.makeDecoder()

        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            voiceprints = []
            return
        }

        do {
            let snapshot = try decoder.decode(VoiceprintSnapshot.self, from: data)
            guard snapshot.schemaVersion == Self.schemaVersion else {
                voiceprints = []
                return
            }
            voiceprints = Self.sortedByEnrollment(snapshot.voiceprints)
        } catch {
            Log.store.error("VoiceprintStore 로드 실패: \(self.fileURL.lastPathComponent, privacy: .public)")
            voiceprints = []
        }
    }

    @discardableResult
    public func add(name: String, embedding: [Float], embeddingModelID: String) -> Bool {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = embeddingModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty, !embedding.isEmpty, !modelID.isEmpty else { return false }

        let voiceprint = Voiceprint(
            displayName: displayName,
            embedding: embedding,
            embeddingModelID: modelID,
            sampleCount: 1
        )
        let next = Self.sortedByEnrollment([voiceprint] + voiceprints)
        guard save(next) else { return false }
        voiceprints = next
        return true
    }

    @discardableResult
    public func rename(id: UUID, to name: String) -> Bool {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return false }
        var next = voiceprints
        guard let index = next.firstIndex(where: { $0.id == id }) else { return false }
        next[index].displayName = displayName

        guard save(next) else { return false }
        voiceprints = next
        return true
    }

    @discardableResult
    public func delete(id: UUID) -> Bool {
        let next = voiceprints.filter { $0.id != id }
        guard next.count != voiceprints.count else { return false }

        guard save(next) else { return false }
        voiceprints = next
        return true
    }

    public func usablePrints(forModelID modelID: String) -> [Voiceprint] {
        voiceprints.filter {
            $0.embeddingModelID == modelID
                && $0.dimensions == $0.embedding.count
                && !$0.embedding.isEmpty
        }
    }

    public var storageDirectory: URL { dir }

    public var snapshotURL: URL { fileURL }

    @discardableResult
    private func save(_ voiceprintsToSave: [Voiceprint]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let snapshot = VoiceprintSnapshot(
                schemaVersion: Self.schemaVersion,
                voiceprints: voiceprintsToSave
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            Log.store.error("VoiceprintStore 저장 실패: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    nonisolated private static func sortedByEnrollment(_ voiceprints: [Voiceprint]) -> [Voiceprint] {
        voiceprints.sorted { $0.enrolledAt > $1.enrolledAt }
    }
}

public struct VoiceprintSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let voiceprints: [Voiceprint]

    public init(schemaVersion: Int, voiceprints: [Voiceprint]) {
        self.schemaVersion = schemaVersion
        self.voiceprints = voiceprints
    }
}
