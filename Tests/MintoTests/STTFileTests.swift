import Testing
@testable import MintoCore
import Foundation
import AVFoundation
import CoreMedia

/// 실제 MP4/TS 파일로 전사 정확도를 측정합니다.
/// 실행: RUN_STT_TESTS=1 swift test -c release --filter STTFileTests
@MainActor
@Suite("STT File Accuracy Tests (Manual Only)", .serialized)
struct STTFileTests {

    private static let sampleDir: URL = {
        // Tests/MintoTests/ → Tests/ → package root → sample/
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample")
    }()

    @Test("실제 MP4 파일 전사 정확도 측정 (30초 청크)")
    func mp4TranscriptionAccuracy() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1" else { return }

        let mp4URL    = Self.sampleDir.appendingPathComponent("you/audio/test.mp4")
        let scriptURL = Self.sampleDir.appendingPathComponent("you/script/test.transcription.txt")

        guard FileManager.default.fileExists(atPath: mp4URL.path) else {
            Issue.record("test.mp4 없음: \(mp4URL.path)")
            return
        }

        let referenceText = try parseScriptText(from: scriptURL)
        print("[FileTest] 참조 텍스트 글자 수: \(referenceText.filter { !$0.isWhitespace }.count)")

        let service = STTService()
        await service.loadModel(variant: "openai_whisper-large-v3-v20240930_turbo")
        guard case .loaded = service.modelState else {
            Issue.record("모델 로드 실패: \(service.modelState)")
            return
        }

        let allSamples = try await extractPCM(from: mp4URL)
        let durationSec = Double(allSamples.count) / 16000
        print("[FileTest] 오디오: \(allSamples.count) samples = \(String(format: "%.1f", durationSec))초")

        // 30초 청크로 순차 전사
        let chunkSize = 16000 * 30
        var transcription = ""
        var idx = 0
        var offset = 0
        while offset < allSamples.count {
            let end   = min(offset + chunkSize, allSamples.count)
            let chunk = Array(allSamples[offset..<end])
            let result = try await service.transcribe(pcmSamples: chunk)
            if !result.segment.text.isEmpty {
                print("[FileTest] 청크 \(idx) (\(String(format: "%.0f", Double(offset)/16000))s): \(result.segment.text)")
                transcription += result.segment.text + " "
            }
            offset += chunkSize
            idx += 1
        }

        let cer = characterErrorRate(reference: referenceText, hypothesis: transcription)

        print("""

=== MP4 전사 정확도 보고서 ===
참조 글자 수 : \(referenceText.filter { !$0.isWhitespace && !$0.isPunctuation }.count)
전사 글자 수 : \(transcription.filter { !$0.isWhitespace && !$0.isPunctuation }.count)
CER          : \(String(format: "%.1f%%", cer * 100))
정확도        : \(String(format: "%.1f%%", (1 - cer) * 100))
==============================

--- 전사 결과 ---
\(transcription.trimmingCharacters(in: .whitespacesAndNewlines))
""")

        #expect(cer < 0.40, "CER 40% 미만이어야 합니다. 실제: \(String(format: "%.1f%%", cer * 100))")
    }

    @Test("sample 첫 청크 전사 → Codex 교정 비교")
    func transcribeThenCorrect() async throws {
        guard ProcessInfo.processInfo.environment["RUN_CORRECTION_TEST"] == "1" else { return }

        let mp4URL = Self.sampleDir.appendingPathComponent("you/audio/test.mp4")
        guard FileManager.default.fileExists(atPath: mp4URL.path) else {
            Issue.record("test.mp4 없음: \(mp4URL.path)")
            return
        }

        let service = STTService()
        await service.loadModel(variant: "openai_whisper-large-v3-v20240930_turbo")
        guard case .loaded = service.modelState else {
            Issue.record("모델 로드 실패: \(service.modelState)")
            return
        }

        // 첫 30초 청크만 전사 (교정 검증용 세그먼트 확보)
        let allSamples = try await extractPCM(from: mp4URL)
        let chunkSize = 16000 * 30
        let firstChunk = Array(allSamples[0..<min(chunkSize, allSamples.count)])
        let raw = try await service.transcribe(pcmSamples: firstChunk).segment.text
        print("[CorrectionTest] 원본 전사:\n\(raw)")

        guard CodexOAuthService.shared.isLoggedIn else {
            Issue.record("Codex 미로그인 — 앱에서 먼저 로그인 필요")
            return
        }

        let corrected = try await CodexOAuthService.shared.correct(text: raw, context: "")
        print("""

=== Codex 교정 비교 ===
원본  : \(raw)
교정본: \(corrected)
=======================
""")

        #expect(!corrected.isEmpty, "교정본이 비어있지 않아야 합니다")
    }

    // MARK: - 오디오 → PCM 추출
    // MPEG-TS 파일이 .mp4 확장자로 저장된 경우 avconvert가 포맷을 잘못 인식합니다.
    // .ts 확장자로 복사 → avconvert(M4A 추출) → afconvert(WAV 변환) 파이프라인을 사용합니다.

    private func extractPCM(from url: URL) async throws -> [Float] {
        let tmp    = URL(fileURLWithPath: NSTemporaryDirectory())
        let tsURL  = tmp.appendingPathComponent("minto_input.ts")
        let m4aURL = tmp.appendingPathComponent("minto_audio.m4a")
        let wavURL = tmp.appendingPathComponent("minto_audio.wav")

        // .ts 확장자로 복사해야 avconvert가 MPEG-TS 포맷을 올바르게 인식합니다
        try? FileManager.default.removeItem(at: tsURL)
        try FileManager.default.copyItem(at: url, to: tsURL)

        // 1단계: avconvert로 오디오 트랙 추출 (MPEG-TS → M4A)
        try runProcess("/usr/bin/avconvert",
                       args: ["--source", tsURL.path, "--output", m4aURL.path,
                              "--preset", "PresetAppleM4A", "--replace"])

        // 2단계: afconvert로 16kHz float PCM WAV 변환
        try runProcess("/usr/bin/afconvert",
                       args: ["-f", "WAVE", "-d", "LEF32@16000", "-c", "1",
                              m4aURL.path, wavURL.path])

        return try readWAVSamples(from: wavURL)
    }

    private func runProcess(_ executable: String, args: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "STTFile", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(executable) 실패: \(errMsg.prefix(200))"])
        }
    }

    private func readWAVSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let marker = Data([0x64, 0x61, 0x74, 0x61]) // "data"
        guard let range = data.range(of: marker) else {
            throw NSError(domain: "STTFile", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "WAV data chunk 없음"])
        }
        let offset = range.upperBound + 4
        guard data.count > offset else {
            throw NSError(domain: "STTFile", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "WAV 데이터 너무 짧음"])
        }
        return data.subdata(in: offset..<data.count).withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self))
        }
    }

    // MARK: - 스크립트 파싱

    private func parseScriptText(from url: URL) throws -> String {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") }
            .joined(separator: " ")
    }

    // MARK: - CER

    private func characterErrorRate(reference: String, hypothesis: String) -> Double {
        let strip: (String) -> [Character] = { s in
            Array(s.filter { !$0.isWhitespace && !$0.isPunctuation })
        }
        let ref = strip(reference)
        let hyp = strip(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    private func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var dp = Array(0...n)
        for i in 1...m {
            var prev = dp[0]
            dp[0] = i
            for j in 1...n {
                let tmp = dp[j]
                dp[j] = a[i-1] == b[j-1] ? prev : Swift.min(prev, Swift.min(dp[j], dp[j-1])) + 1
                prev = tmp
            }
        }
        return dp[n]
    }
}
