import os
import Foundation

/// 디스크 저장 실패 시 전사·요약 데이터를 복구 파일로 보존하고, 앱 재시작 시 자동 복원한다.
/// 저장 위치: ~/Library/Application Support/Minto/recovery/<timestamp>_<id>.{md,json}
/// - .md: 사람용 백업 (기존 동작 유지)
/// - .json: 프로그래밍 복원용 (MeetingRecord Codable)
///
/// AppDelegate에서 직접 인라인으로 처리하지 않고 이 타입으로 분리해 단위 테스트가 가능하게 한다.
public enum MeetingSaveRecovery {

    /// 복구 파일을 기록한다. .md(사람용)와 .json(복원용)을 동시에 저장한다.
    /// - Parameters:
    ///   - record: 저장에 실패한 회의 기록.
    ///   - recoveryDirectory: 복구 파일을 쓸 디렉터리. nil이면 기본 경로를 사용.
    public static func writeRecoveryFile(
        for record: MeetingRecord,
        recoveryDirectory: URL? = nil
    ) {
        let dir = recoveryDirectory ?? defaultRecoveryDirectory()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Log.store.error("복구 디렉터리 생성 실패: \(error.localizedDescription, privacy: .public)")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: record.startedAt)
            .replacingOccurrences(of: ":", with: "-")
        let stem = "\(timestamp)_\(record.id.uuidString)"

        // .md: 사람용 백업
        let mdURL = dir.appendingPathComponent("\(stem).md")
        let content = buildMarkdown(for: record)
        do {
            try Data(content.utf8).write(to: mdURL, options: .atomic)
            Log.store.info("복구 파일 저장됨: \(mdURL.lastPathComponent, privacy: .public)")
        } catch {
            Log.store.error("복구 파일 쓰기 실패: \(error.localizedDescription, privacy: .public)")
        }

        // .json: 프로그래밍 복원용
        let jsonURL = dir.appendingPathComponent("\(stem).json")
        let encoder = MeetingRecordCoding.makeEncoder()
        guard let data = try? encoder.encode(record) else {
            Log.store.error("복구 JSON 인코딩 실패: \(record.id.uuidString, privacy: .public)")
            return
        }
        do {
            try data.write(to: jsonURL, options: .atomic)
            Log.store.info("복구 JSON 저장됨: \(jsonURL.lastPathComponent, privacy: .public)")
        } catch {
            Log.store.error("복구 JSON 쓰기 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 자동 복원

    /// recovery/*.json 전체를 디코드해 store에 upsert한다.
    /// - 디코드 실패(손상 파일): 파일 유지 + Log.store.error, 다음 파일 계속
    /// - store.save() == .success: .json + 짝 .md 삭제
    /// - store.save() != .success: 파일 유지 + Log.store.error
    /// - 반환값: 복원 성공 건수
    @MainActor
    public static func restorePendingRecords(
        into store: MeetingStore,
        recoveryDirectory: URL? = nil
    ) -> Int {
        let dir = recoveryDirectory ?? defaultRecoveryDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        let jsonURLs = urls.filter { $0.pathExtension == "json" }
        guard !jsonURLs.isEmpty else { return 0 }

        let decoder = MeetingRecordCoding.makeDecoder()
        var successCount = 0
        var failCount = 0

        for jsonURL in jsonURLs {
            guard let data = try? Data(contentsOf: jsonURL),
                  let record = try? decoder.decode(MeetingRecord.self, from: data) else {
                Log.store.error("복구 파일 디코드 실패: \(jsonURL.lastPathComponent, privacy: .public)")
                failCount += 1
                continue
            }

            let result = store.save(record)
            switch result {
            case .success:
                try? FileManager.default.removeItem(at: jsonURL)
                let mdURL = jsonURL.deletingPathExtension().appendingPathExtension("md")
                try? FileManager.default.removeItem(at: mdURL)
                successCount += 1
            case .failed:
                Log.store.error("복구 재저장 실패 — 파일 유지: \(jsonURL.lastPathComponent, privacy: .public)")
                failCount += 1
            case .skippedEmpty:
                Log.store.error("복구 파일이 빈 회의 — 파일 유지: \(jsonURL.lastPathComponent, privacy: .public)")
                failCount += 1
            }
        }

        if failCount > 0 {
            Log.store.error("복원 실패 \(failCount, privacy: .public)건, 파일 유지")
        }

        return successCount
    }

    // MARK: - Internal

    static func defaultRecoveryDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Minto/recovery", isDirectory: true)
    }

    static func buildMarkdown(for record: MeetingRecord) -> String {
        let titleText = record.title.isEmpty ? "회의" : record.title
        var out = "# \(titleText)\n\n"

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        out += "_\(formatter.string(from: record.startedAt)) · "
        out += MeetingRecord.durationText(record.durationSeconds)
        out += "_\n\n"

        let summaryMd = record.summary.markdown()
        if !summaryMd.isEmpty {
            out += summaryMd + "\n\n"
        }

        if !record.transcript.isEmpty {
            out += "## 전사\n\n"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss"
            out += record.transcript
                .map { seg in
                    let t = timeFormatter.string(from: seg.timestamp)
                    return "**[\(t)]** \(seg.text)"
                }
                .joined(separator: "\n\n")
            out += "\n"
        }

        return out
    }
}
