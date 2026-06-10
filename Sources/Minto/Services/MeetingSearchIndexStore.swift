import os
import Foundation

public struct MeetingSearchIndexSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let chunkingVersion: Int
    public let generatedAt: Date
    public let chunks: [MeetingSearchChunk]

    public init(
        schemaVersion: Int = MeetingSearchIndex.schemaVersion,
        chunkingVersion: Int = MeetingSearchIndex.chunkingVersion,
        generatedAt: Date = Date(),
        chunks: [MeetingSearchChunk]
    ) {
        self.schemaVersion = schemaVersion
        self.chunkingVersion = chunkingVersion
        self.generatedAt = generatedAt
        self.chunks = chunks
    }

    public var isCompatible: Bool {
        schemaVersion == MeetingSearchIndex.schemaVersion
            && chunkingVersion == MeetingSearchIndex.chunkingVersion
            && chunks.allSatisfy { $0.chunkingVersion == chunkingVersion }
    }

    public var index: MeetingSearchIndex {
        MeetingSearchIndex(chunks: chunks)
    }
}

public struct MeetingSearchIndexStore: Sendable {
    public let indexURL: URL

    public init(directory: URL) {
        indexURL = directory.appendingPathComponent("search-index.v\(MeetingSearchIndex.schemaVersion).mintoindex")
    }

    @discardableResult
    public func rebuild(from records: [MeetingRecord]) -> MeetingSearchIndex {
        let index = MeetingSearchIndex(records: records)
        save(index)
        return index
    }

    /// 디스크의 인덱스 파일을 삭제한다.
    /// save() 실패 후 stale 캐시가 남지 않도록 호출한다.
    public func invalidate() {
        try? FileManager.default.removeItem(at: indexURL)
    }

    public func load() -> MeetingSearchIndex? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        guard let snapshot = try? Self.decoder.decode(MeetingSearchIndexSnapshot.self, from: data) else {
            Log.search.error("인덱스 디코딩 실패 — 재생성이 필요합니다.")
            return nil
        }
        guard snapshot.isCompatible else {
            Log.search.error("인덱스 버전 불일치 — 재생성이 필요합니다.")
            return nil
        }
        return snapshot.index
    }

    @discardableResult
    public func save(_ index: MeetingSearchIndex) -> Bool {
        let snapshot = MeetingSearchIndexSnapshot(chunks: index.chunks)
        guard let data = try? Self.encoder.encode(snapshot) else {
            Log.search.error("인덱스 인코딩 실패")
            return false
        }
        do {
            // `.atomic` writes to a temporary file and renames it into place, so the
            // sidecar remains a safe cache even if the app exits during index save.
            try data.write(to: indexURL, options: .atomic)
            return true
        } catch {
            Log.search.error("인덱스 저장 실패: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }

    private static var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
