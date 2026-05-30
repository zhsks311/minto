import Testing
@testable import MintoCore
import Foundation

/// AI Hub Korean speech corpus G2 샘플로 전사 CER을 측정합니다.
/// 실행: RUN_STT_TESTS=1 swift test -c release --filter STTG2Tests
@MainActor
@Suite("G2 Corpus CER Evaluation (Manual Only)", .serialized)
struct STTG2Tests {

    private static let sampleDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MintoTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("sample")
    }()

    private static let model = "openai_whisper-large-v3-v20240930_turbo"
    private static let maxFilesPerSession = 50

    private static let sessions = [
        "S000012",
        "S000013",
        "S000017",
        "S000018",
        "S000019",
        "S000023",
        "S000027",
    ]

    @Test("G2 코퍼스 세션별 CER 측정")
    func g2CorpusCER() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1" else { return }

        let service = STTService()
        await service.loadModel(variant: Self.model)
        guard case .loaded = service.modelState else {
            Issue.record("모델 로드 실패: \(service.modelState)")
            return
        }

        var allCERs: [Double] = []

        print("\n=== G2 Corpus CER Evaluation [\(Self.model)] ===")

        for session in Self.sessions {
            let pairs = try Self.samplePairs(for: session).prefix(Self.maxFilesPerSession)
            guard !pairs.isEmpty else {
                Issue.record("G2 paired samples 없음: \(session)")
                continue
            }

            var sessionCERs: [Double] = []

            for pair in pairs {
                let reference = try Self.parseG2ScriptText(from: pair.scriptURL)
                let samples = try Self.readWAVSamples(from: pair.audioURL)
                let result = try await service.transcribe(pcmSamples: samples)
                let cer = Self.characterErrorRate(
                    reference: reference,
                    hypothesis: result.segment.text
                )

                sessionCERs.append(cer)
                allCERs.append(cer)

                print("[G2] \(session)/\(pair.id): CER \(String(format: "%.1f%%", cer * 100))")
            }

            let sessionCER = sessionCERs.reduce(0, +) / Double(sessionCERs.count)
            print("[G2] \(session) average CER: \(String(format: "%.1f%%", sessionCER * 100)) (\(sessionCERs.count) samples)")
        }

        guard !allCERs.isEmpty else {
            Issue.record("G2 평가 대상 샘플이 없습니다")
            return
        }

        let overallCER = allCERs.reduce(0, +) / Double(allCERs.count)

        print("""
────────────────────────────────────────
전체 샘플 수 : \(allCERs.count)
평균 CER    : \(String(format: "%.1f%%", overallCER * 100))
평균 정확도 : \(String(format: "%.1f%%", (1 - overallCER) * 100))
========================================

""")

        #expect(overallCER < 0.35, "전체 평균 CER 35% 미만이어야 합니다. 실제: \(String(format: "%.1f%%", overallCER * 100))")
    }

    // MARK: - G2 sample discovery

    private static func samplePairs(for session: String) throws -> [(id: String, audioURL: URL, scriptURL: URL)] {
        let audioDir = sampleDir.appendingPathComponent("g2/audio/\(session)")
        let scriptDir = sampleDir.appendingPathComponent("g2/script/\(session)")

        let fileManager = FileManager.default

        let audioIDs = Set(try fileManager.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "wav" }
            .map { $0.deletingPathExtension().lastPathComponent })

        let scriptIDs = Set(try fileManager.contentsOfDirectory(at: scriptDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "txt" }
            .map { $0.deletingPathExtension().lastPathComponent })

        return audioIDs.intersection(scriptIDs)
            .sorted()
            .map { id in
                (
                    id: id,
                    audioURL: audioDir.appendingPathComponent("\(id).wav"),
                    scriptURL: scriptDir.appendingPathComponent("\(id).txt")
                )
            }
    }

    // MARK: - WAV loading (16-bit PCM 및 Float32 지원)

    private static func readWAVSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)

        guard data.count >= 12,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE"
        else {
            throw NSError(domain: "STTG2", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "WAV RIFF 헤더가 아닙니다: \(url.path)"
            ])
        }

        var audioFormat: UInt16?
        var channelCount: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var dataRange: Range<Int>?

        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<offset + 4], encoding: .ascii) ?? ""
            let chunkSize = Int(readUInt32LE(data, offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(chunkStart + chunkSize, data.count)

            if chunkID == "fmt ", chunkStart + 16 <= chunkEnd {
                audioFormat = readUInt16LE(data, chunkStart)
                channelCount = readUInt16LE(data, chunkStart + 2)
                sampleRate = readUInt32LE(data, chunkStart + 4)
                bitsPerSample = readUInt16LE(data, chunkStart + 14)
            } else if chunkID == "data" {
                dataRange = chunkStart..<chunkEnd
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard channelCount == 1, sampleRate == 16_000 else {
            throw NSError(domain: "STTG2", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "G2 WAV는 16kHz mono여야 합니다: \(url.path)"
            ])
        }

        guard let audioFormat, let bitsPerSample, let dataRange else {
            throw NSError(domain: "STTG2", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "WAV fmt/data chunk를 찾을 수 없습니다: \(url.path)"
            ])
        }

        switch (audioFormat, bitsPerSample) {
        case (1, 16):
            // PCM 16-bit signed → Float [-1, 1)
            return stride(from: dataRange.lowerBound, to: dataRange.upperBound - 1, by: 2).map { index in
                let sample = Int16(bitPattern: readUInt16LE(data, index))
                return max(-1.0, Float(sample) / 32768.0)
            }

        case (3, 32):
            // IEEE Float 32-bit
            return stride(from: dataRange.lowerBound, to: dataRange.upperBound - 3, by: 4).map { index in
                Float(bitPattern: readUInt32LE(data, index))
            }

        default:
            throw NSError(domain: "STTG2", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "지원하지 않는 WAV 포맷입니다: format=\(audioFormat), bits=\(bitsPerSample), path=\(url.path)"
            ])
        }
    }

    private static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    // MARK: - G2 script parsing

    private static func parseG2ScriptText(from url: URL) throws -> String {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let joined = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // (표준형)/(발음형) → 표준형 (ASCII 영문이면 발음형 우선)
        let pairResolved = replaceStandardPronunciationPairs(in: joined)
        // n/, b/, l/, o/, n/o/ 등 태그 제거
        let tagRemoved = removeSlashTags(from: pairResolved)
        let plusRemoved = tagRemoved.replacingOccurrences(of: "+", with: "")

        return plusRemoved
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// `(표준형)/(발음형)` 패턴 → 표준형 (표준형이 ASCII 영문만이면 발음형 선택)
    private static func replaceStandardPronunciationPairs(in text: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"\(([^()]*)\)\s*/\s*\(([^()]*)\)"#)
        var result = text
        let fullRange = NSRange(location: 0, length: (result as NSString).length)
        let matches = regex.matches(in: result, range: fullRange)

        for match in matches.reversed() {
            let nsResult = result as NSString
            let first = nsResult.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let second = nsResult.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = preferredStandardText(first: first, second: second)
            result = nsResult.replacingCharacters(in: match.range, with: replacement)
        }

        return result
    }

    private static func preferredStandardText(first: String, second: String) -> String {
        if isASCIILettersOnly(first), !second.isEmpty {
            return second
        }
        return first.isEmpty ? second : first
    }

    private static func isASCIILettersOnly(_ text: String) -> Bool {
        let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return !text.isEmpty && text.unicodeScalars.allSatisfy { letters.contains($0) }
    }

    /// `token/` 형태의 슬래시 태그 제거 (n/, b/, l/, o/, n/o/ 등)
    private static func removeSlashTags(from text: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"(^|\s)[^\s/()]+/\s*"#)
        var result = text

        while true {
            let range = NSRange(location: 0, length: (result as NSString).length)
            let updated = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: " "
            )
            if updated == result { return result }
            result = updated
        }
    }

    // MARK: - CER

    private static func characterErrorRate(reference: String, hypothesis: String) -> Double {
        let strip: (String) -> [Character] = { text in
            Array(text.filter { !$0.isWhitespace && !$0.isPunctuation })
        }

        let ref = strip(reference)
        let hyp = strip(hypothesis)

        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    private static func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(0...n)

        for i in 1...m {
            var prev = dp[0]
            dp[0] = i

            for j in 1...n {
                let tmp = dp[j]
                dp[j] = a[i - 1] == b[j - 1]
                    ? prev
                    : Swift.min(prev, Swift.min(dp[j], dp[j - 1])) + 1
                prev = tmp
            }
        }

        return dp[n]
    }
}
