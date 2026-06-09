import Foundation
import Combine

/// 회의 기록을 JSON으로 영속화하고 목록을 제공한다.
/// 저장 위치: ~/Library/Application Support/Minto/meetings/{id}.json
/// 손상된 파일은 조용히 건너뛴다(fail-soft). 목록은 시작 시각 내림차순.
@MainActor
public final class MeetingStore: ObservableObject {

    public static let shared = MeetingStore()

    /// 최신순 회의 목록.
    @Published public private(set) var meetings: [MeetingRecord] = []

    private let dir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let searchIndexStore: MeetingSearchIndexStore

    /// - Parameter directory: 저장 디렉터리. nil이면 ~/Library/Application Support/Minto/meetings (테스트는 temp 주입).
    public init(directory: URL? = nil) {
        if let directory {
            dir = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            dir = base.appendingPathComponent("Minto/meetings", isDirectory: true)
        }
        searchIndexStore = MeetingSearchIndexStore(directory: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        decoder = dec

        reload()
    }

    /// 디스크에서 전체 목록을 다시 읽는다. 손상 항목은 skip.
    public func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var loaded: [MeetingRecord] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(MeetingRecord.self, from: data) else {
                fputs("[MeetingStore] 손상/디코드 실패 skip: \(url.lastPathComponent)\n", stderr)
                continue
            }
            loaded.append(record)
        }
        meetings = loaded.sorted { $0.startedAt > $1.startedAt }
        rebuildSearchIndex()
    }

    /// 회의를 저장한다. 빈 회의(전사·요약 없음)는 저장하지 않는다. 성공 시 true.
    @discardableResult
    public func save(_ record: MeetingRecord) -> Bool {
        guard !record.isEmpty else {
            fputs("[MeetingStore] 빈 회의 — 저장 생략\n", stderr)
            return false
        }
        guard let data = try? encoder.encode(record) else {
            fputs("[MeetingStore] 인코딩 실패\n", stderr)
            return false
        }
        let url = dir.appendingPathComponent("\(record.id.uuidString).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            fputs("[MeetingStore] 저장 실패: \(error.localizedDescription)\n", stderr)
            return false
        }
        meetings.removeAll { $0.id == record.id }
        meetings.append(record)
        meetings.sort { $0.startedAt > $1.startedAt }
        rebuildSearchIndex()
        return true
    }

    /// 회의를 삭제한다.
    public func delete(_ id: UUID) {
        let url = dir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        meetings.removeAll { $0.id == id }
        rebuildSearchIndex()
    }

    /// 저장 디렉터리(테스트·export 기본 경로 참고용).
    public var storageDirectory: URL { dir }

    public var searchIndexURL: URL { searchIndexStore.indexURL }

    private func rebuildSearchIndex() {
        searchIndexStore.rebuild(from: meetings)
    }
}
