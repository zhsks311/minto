import AVFoundation
import Foundation

/// 녹음 중 마이크 샘플(16kHz mono)을 로컬 WAV 파일로 보존한다.
///
/// 화자분리·재전사·구간 듣기 같은 사후 처리의 공통 전제다. 파일은 이 Mac의
/// Application Support에만 저장되고 외부로 전송되지 않으며, 보관 기간이 지나면
/// 앱 시작 시 정리된다. 기록 실패는 fail-soft — 전사·저장 흐름에 영향을 주지
/// 않고 `.error` 로그만 남긴다.
final class RecordingAudioArchiver: @unchecked Sendable {
    static let preferenceKey = "recordingAudioRetentionEnabled"
    static let retentionDaysKey = "recordingAudioRetentionDays"
    static let defaultRetentionDays = 30
    static let sampleRate: Double = 16_000

    private let queue = DispatchQueue(label: "minto.recording.audio.archiver", qos: .utility)
    private let directory: URL
    private var file: AVAudioFile?
    private var fileName: String?
    private var writtenFrameCount: AVAudioFramePosition = 0
    private var writeFailed = false

    init(directory: URL = RecordingAudioArchiver.recordingsDirectory) {
        self.directory = directory
    }

    // MARK: - 설정/경로

    static var recordingsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Minto", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: preferenceKey) != nil else { return true }
        return defaults.bool(forKey: preferenceKey)
    }

    static func retentionDays(in defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: retentionDaysKey)
        return stored > 0 ? stored : defaultRetentionDays
    }

    // MARK: - 기록

    func start() {
        queue.async { [self] in
            openFile()
        }
    }

    func append(samples: [Float]) {
        guard !samples.isEmpty else { return }
        queue.async { [self] in
            write(samples)
        }
    }

    /// 파일을 닫고, 실제로 기록된 프레임이 있으면 파일명을 돌려준다.
    /// 빈 파일(무음·기록 실패)은 남기지 않는다.
    func finish() async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let finishedFileName: String?
                if writtenFrameCount > 0, !writeFailed {
                    finishedFileName = fileName
                } else {
                    finishedFileName = nil
                    if let fileName {
                        try? FileManager.default.removeItem(
                            at: directory.appendingPathComponent(fileName)
                        )
                    }
                }
                file = nil
                fileName = nil
                writtenFrameCount = 0
                writeFailed = false
                continuation.resume(returning: finishedFileName)
            }
        }
    }

    private func openFile() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = "\(UUID().uuidString).wav"
            let url = directory.appendingPathComponent(name)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            file = try AVAudioFile(forWriting: url, settings: settings)
            fileName = name
            writtenFrameCount = 0
            writeFailed = false
        } catch {
            writeFailed = true
            Log.audio.error("recording audio archive open failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func write(_ samples: [Float]) {
        guard let file, !writeFailed else { return }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData?[0] else {
            return
        }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        do {
            try file.write(from: buffer)
            writtenFrameCount += AVAudioFramePosition(samples.count)
        } catch {
            // 한 번 실패하면 이후 쓰기를 멈춘다 — 깨진 파일을 키우지 않는다.
            writeFailed = true
            Log.audio.error("recording audio archive write failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 정리

    static func removeArchivedFile(
        named fileName: String,
        in directory: URL = RecordingAudioArchiver.recordingsDirectory
    ) {
        // 저장된 파일명만 받으므로 경로 조작이 끼어들 수 없도록 lastPathComponent로 한정한다.
        let safeName = (fileName as NSString).lastPathComponent
        guard !safeName.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(safeName))
    }

    /// 보관 기간이 지난 녹음 오디오를 지운다. 반환값은 삭제한 파일 수.
    @discardableResult
    static func cleanupExpired(
        retentionDays: Int = retentionDays(),
        now: Date = Date(),
        in directory: URL = RecordingAudioArchiver.recordingsDirectory
    ) -> Int {
        guard retentionDays > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        var removedCount = 0
        for url in urls where url.pathExtension == "wav" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified, modified < cutoff else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removedCount += 1
            } catch {
                Log.audio.error("recording audio cleanup failed file=\(url.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
        return removedCount
    }
}
