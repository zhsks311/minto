import os
import Foundation
import Combine

/// `MeetingStore.save(_:)` 결과.
/// - `.skippedEmpty`: 전사·요약이 모두 없는 빈 회의 → 저장 생략(정상, 데이터 보호 불필요).
/// - `.success`: 디스크 저장 성공.
/// - `.failed`: 내용은 있지만 인코딩 또는 디스크 I/O 실패 → 복구 조치 필요.
public enum MeetingSaveResult {
    case skippedEmpty
    case success
    case failed
}

/// 회의 기록을 JSON으로 영속화하고 목록을 제공한다.
/// 저장 위치: ~/Library/Application Support/Minto/meetings/{id}.json
/// 손상된 파일은 quarantine/으로 옮기고 목록은 시작 시각 내림차순.
@MainActor
public final class MeetingStore: ObservableObject {

    public static let shared = MeetingStore()

    /// 최신순 회의 목록.
    @Published public private(set) var meetings: [MeetingRecord] = []
    /// 마지막 reload에서 격리한 손상 회의 파일 수.
    @Published public private(set) var corruptedCount: Int = 0

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

        encoder = MeetingRecordCoding.makeEncoder()
        decoder = MeetingRecordCoding.makeDecoder()

        reload()
    }

    /// 디스크에서 전체 목록을 다시 읽는다. 손상 항목은 quarantine/으로 보존한다.
    public func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var loaded: [MeetingRecord] = []
        var quarantinedCount = 0
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(MeetingRecord.self, from: data) else {
                Log.store.error("손상/디코드 실패 skip: \(url.lastPathComponent, privacy: .public)")
                if quarantineCorruptedFile(at: url) {
                    quarantinedCount += 1
                }
                continue
            }
            loaded.append(record)
        }
        corruptedCount = quarantinedCount
        meetings = loaded.sorted { $0.startedAt > $1.startedAt }
        rebuildSearchIndex()
    }

    /// 회의를 저장한다. 빈 회의(전사·요약 없음)는 저장하지 않는다.
    /// 반환값: `.skippedEmpty`(빈 회의), `.success`(저장 성공), `.failed`(인코딩/디스크 실패).
    @discardableResult
    public func save(_ record: MeetingRecord) -> MeetingSaveResult {
        guard !record.isEmpty else {
            Log.store.info("빈 회의 — 저장 생략")
            return .skippedEmpty
        }
        guard let data = try? encoder.encode(record) else {
            Log.store.error("인코딩 실패")
            return .failed
        }
        let url = dir.appendingPathComponent("\(record.id.uuidString).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Log.store.error("저장 실패: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
        meetings.removeAll { $0.id == record.id }
        meetings.append(record)
        meetings.sort { $0.startedAt > $1.startedAt }
        rebuildSearchIndex()
        return .success
    }

    /// 회의를 삭제한다. 보존된 녹음 오디오가 있으면 함께 지운다.
    public func delete(_ id: UUID) {
        if let audioFileName = meetings.first(where: { $0.id == id })?.audioFileName {
            RecordingAudioArchiver.removeArchivedFile(named: audioFileName)
        }
        let url = dir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        meetings.removeAll { $0.id == id }
        rebuildSearchIndex()
    }

    /// 저장 디렉터리(테스트·export 기본 경로 참고용).
    public var storageDirectory: URL { dir }

    public var searchIndexURL: URL { searchIndexStore.indexURL }

    private func rebuildSearchIndex() {
        let index = MeetingSearchIndex(records: meetings)
        if !searchIndexStore.save(index) {
            searchIndexStore.invalidate()
        }
    }

    private func quarantineCorruptedFile(at url: URL) -> Bool {
        let quarantineDir = dir.appendingPathComponent("quarantine", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
            let destination = quarantineDestination(for: url, in: quarantineDir)
            try FileManager.default.moveItem(at: url, to: destination)
            return true
        } catch {
            Log.store.error("손상 파일 격리 실패: \(url.lastPathComponent, privacy: .public)")
            return false
        }
    }

    private func quarantineDestination(for url: URL, in quarantineDir: URL) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        var candidate = quarantineDir.appendingPathComponent(url.lastPathComponent)
        var suffix = 1

        while FileManager.default.fileExists(atPath: candidate.path) {
            let filename = "\(stem)-\(suffix)"
            candidate = quarantineDir.appendingPathComponent(filename)
            if !pathExtension.isEmpty {
                candidate = candidate.appendingPathExtension(pathExtension)
            }
            suffix += 1
        }

        return candidate
    }
}
