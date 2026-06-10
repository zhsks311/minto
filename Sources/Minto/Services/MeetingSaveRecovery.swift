import os
import Foundation

/// 디스크 저장 실패 시 전사·요약 데이터를 복구 파일로 보존한다.
/// 저장 위치: ~/Library/Application Support/Minto/recovery/<timestamp>_<id>.md
///
/// AppDelegate에서 직접 인라인으로 처리하지 않고 이 타입으로 분리해 단위 테스트가 가능하게 한다.
public enum MeetingSaveRecovery {

    /// 복구 파일을 기록한다. 전체 경로는 stderr 로그에만 남긴다.
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
        let filename = "\(timestamp)_\(record.id.uuidString).md"
        let fileURL = dir.appendingPathComponent(filename)

        let content = buildMarkdown(for: record)
        do {
            try Data(content.utf8).write(to: fileURL, options: .atomic)
            Log.store.info("복구 파일 저장됨: \(fileURL.lastPathComponent, privacy: .public)")
        } catch {
            Log.store.error("복구 파일 쓰기 실패: \(error.localizedDescription, privacy: .public)")
        }
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
