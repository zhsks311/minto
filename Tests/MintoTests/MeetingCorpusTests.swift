import Testing
@testable import MintoCore
import Foundation

/// 국회 영상회의록(실제 회의 음성 + 공식 SMI 자막)으로 전사 CER을 측정한다.
///
/// g2(깨끗한 낭독)와 달리 즉흥·다중화자·격식 한국어 회의체라, suppressBlank·prompt
/// priming·할루시네이션 필터처럼 "깨끗한 음성에선 발동하지 않는" 변경의 효과를 실제로
/// 측정할 수 있는 코퍼스다.
///
/// 자료(`sample/meeting/`)는 국회법 149조2항(비상업)·공공누리(출처표시) 대상이라
/// .gitignore로 커밋에서 제외한다. 내부 측정 전용, 재배포 금지.
///
/// 준비:
///   1. SMI 정답:  sample/meeting/raw/haengan_20260526_smi.json  ({smiList:[{start,cc,end}]})
///   2. 오디오:    sample/meeting/raw/haengan_20260526_full.wav   (16kHz mono PCM)
/// 실행:
///   RUN_STT_TESTS=1 swift test -c release --filter MeetingCorpusTests
///   (옵션) MEETING_WINDOW_SEC=20 MEETING_MAX_WINDOWS=60 으로 창 크기·개수 조절
@MainActor
@Suite("Meeting Corpus CER Evaluation (Manual Only)", .serialized)
struct MeetingCorpusTests {

    private static let rawDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MintoTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("sample/meeting/raw")
    }()

    // 측정 대상 파일명. 기본은 행안위 회의, MEETING_WAV/MEETING_SMI로 다른 회의 지정 가능
    // (sample/fetch-assembly-meeting.sh가 만든 다른 파일명을 코드 수정 없이 측정).
    private static var audioURL: URL {
        rawDir.appendingPathComponent(ProcessInfo.processInfo.environment["MEETING_WAV"] ?? "haengan_20260526_full.wav")
    }
    private static var smiURL: URL {
        rawDir.appendingPathComponent(ProcessInfo.processInfo.environment["MEETING_SMI"] ?? "haengan_20260526_smi.json")
    }

    private static let model = "openai_whisper-large-v3-v20240930_turbo"
    private static let sampleRate = 16_000

    /// 연속 자막을 이 길이(초)에 도달할 때까지 병합해 한 창으로 만든다.
    private static var windowSeconds: Double {
        ProcessInfo.processInfo.environment["MEETING_WINDOW_SEC"].flatMap(Double.init) ?? 20.0
    }

    /// 측정할 최대 창 수(빠른 1차 검증용). 0 이하이면 전체.
    private static var maxWindows: Int {
        ProcessInfo.processInfo.environment["MEETING_MAX_WINDOWS"].flatMap(Int.init) ?? 60
    }

    /// 자막 사이 간격이 이 값(초)을 넘으면 창을 끊는다(침묵/정회 구간을 클립에서 배제).
    /// 앱 VAD의 침묵 컷(1.5초)과 정렬해, 긴 침묵을 가로질러 병합하는 것을 막는다.
    private static let maxGapSeconds: Double = 1.5

    @Test("국회 회의 코퍼스 창 단위 CER 측정")
    func meetingCorpusCER() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1" else { return }

        // 자료가 없으면(미다운로드) 조용히 skip — CI/일반 테스트에서 실패하지 않도록.
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: Self.audioURL.path),
              fileManager.fileExists(atPath: Self.smiURL.path)
        else {
            print("[Meeting] 자료 없음 — skip (\(Self.audioURL.lastPathComponent), \(Self.smiURL.lastPathComponent))")
            return
        }

        let captions = try Self.parseSMI(from: Self.smiURL)
        let windows = Self.mergeIntoWindows(captions, windowSeconds: Self.windowSeconds)
        let targetWindows = Self.maxWindows > 0 ? Array(windows.prefix(Self.maxWindows)) : windows
        guard !targetWindows.isEmpty else {
            Issue.record("병합된 창이 없습니다")
            return
        }

        let samples = try Self.readWAVSamples(from: Self.audioURL)

        let service = STTService()
        await service.loadModel(variant: Self.model)
        guard case .loaded = service.modelState else {
            Issue.record("모델 로드 실패: \(service.modelState)")
            return
        }

        print("\n=== Meeting Corpus CER [\(Self.model)] (window=\(Self.windowSeconds)s, \(targetWindows.count)/\(windows.count) windows) ===")

        // micro-average: 총 편집거리 / 총 참조글자. 길이가 제각각인 창에서 짧은 창의
        // 노이즈(3글자 창의 1오류=33%)가 큰 분모에 희석돼 macro-average보다 안정적이다.
        var totalDistance = 0
        var totalRefLen = 0
        var windowCount = 0
        for (index, window) in targetWindows.enumerated() {
            let startSample = max(0, Int(window.start * Double(Self.sampleRate)))
            let endSample = min(samples.count, Int(window.end * Double(Self.sampleRate)))
            guard endSample > startSample else { continue }

            let clip = Array(samples[startSample..<endSample])
            let result = try await service.transcribe(pcmSamples: clip)
            let stats = Self.cerStats(reference: window.text, hypothesis: result.segment.text)
            totalDistance += stats.distance
            totalRefLen += stats.refLen
            windowCount += 1
            let windowCER = stats.refLen > 0 ? Double(stats.distance) / Double(stats.refLen) : 0

            print(String(format: "[Meeting] #%03d %6.1f–%6.1fs CER %.1f%%", index, window.start, window.end, windowCER * 100))
            if ProcessInfo.processInfo.environment["MEETING_DEBUG"] == "1" {
                print("    REF: \(window.text.prefix(120))")
                print("    HYP: \(result.segment.text.prefix(120))")
            }
        }

        guard windowCount > 0, totalRefLen > 0 else {
            Issue.record("측정된 창이 없습니다")
            return
        }

        let microCER = Double(totalDistance) / Double(totalRefLen)
        print("""
        ────────────────────────────────────────
        창 수             : \(windowCount)
        micro-average CER : \(String(format: "%.1f%%", microCER * 100)) (편집거리 \(totalDistance) / 참조 \(totalRefLen)자)
        ========================================
        ※ 방송 자막은 표시 타이밍이 느슨하고 비verbatim(속기 편집)이라 절대 CER에는 환원
          불가능한 바닥이 있다. 이 수치는 동일 오디오에서 설정 A/B의 *상대* 비교용이다.

        """)

        // 측정 하니스이므로 회귀 게이트가 아닌 느슨한 sanity bound만 둔다.
        #expect(microCER < 0.80, "micro-CER sanity bound 초과: \(String(format: "%.1f%%", microCER * 100))")
    }

    // MARK: - SMI 파싱

    private struct SMIDocument: Decodable {
        let smiList: [Caption]
    }

    private struct Caption: Decodable {
        let start: Double
        let end: Double
        let cc: String
    }

    private struct Window {
        let start: Double
        let end: Double
        let text: String
    }

    private static func parseSMI(from url: URL) throws -> [Caption] {
        let data = try Data(contentsOf: url)
        let doc = try JSONDecoder().decode(SMIDocument.self, from: data)
        return doc.smiList
            .filter { !$0.cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
    }

    /// 연속 자막을 windowSeconds에 도달할 때까지 병합한다.
    /// 창 start = 첫 자막 start, end = 마지막 자막 end, text = cc 이어붙임.
    private static func mergeIntoWindows(_ captions: [Caption], windowSeconds: Double) -> [Window] {
        var windows: [Window] = []
        var bucket: [Caption] = []

        func flush() {
            guard let first = bucket.first, let last = bucket.last else { return }
            let text = bucket.map { $0.cc.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
            windows.append(Window(start: first.start, end: last.end, text: text))
            bucket = []
        }

        for caption in captions {
            // 직전 자막과 간격이 크면(침묵/정회) 현재 창을 먼저 닫아 침묵을 클립에서 배제한다.
            if let last = bucket.last, caption.start - last.end > maxGapSeconds {
                flush()
            }
            bucket.append(caption)
            if let first = bucket.first, caption.end - first.start >= windowSeconds {
                flush()
            }
        }
        flush()
        return windows
    }

    // MARK: - WAV 로딩 (16-bit PCM / Float32) — STTG2Tests와 동일 포맷 가정

    private static func readWAVSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)

        guard data.count >= 12,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE"
        else {
            throw NSError(domain: "Meeting", code: 1, userInfo: [
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
            throw NSError(domain: "Meeting", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "회의 WAV는 16kHz mono여야 합니다: \(url.path)"
            ])
        }

        guard let audioFormat, let bitsPerSample, let dataRange else {
            throw NSError(domain: "Meeting", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "WAV fmt/data chunk를 찾을 수 없습니다: \(url.path)"
            ])
        }

        switch (audioFormat, bitsPerSample) {
        case (1, 16):
            return stride(from: dataRange.lowerBound, to: dataRange.upperBound - 1, by: 2).map { index in
                let sample = Int16(bitPattern: readUInt16LE(data, index))
                return max(-1.0, Float(sample) / 32768.0)
            }
        case (3, 32):
            return stride(from: dataRange.lowerBound, to: dataRange.upperBound - 3, by: 4).map { index in
                Float(bitPattern: readUInt32LE(data, index))
            }
        default:
            throw NSError(domain: "Meeting", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "지원하지 않는 WAV 포맷: format=\(audioFormat), bits=\(bitsPerSample)"
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

    // MARK: - CER (STTG2Tests와 동일 정의: 공백·문장부호 제거 후 편집거리)

    /// 공백·문장부호 제거 후 편집거리와 참조 길이를 반환한다(micro-average 집계용).
    private static func cerStats(reference: String, hypothesis: String) -> (distance: Int, refLen: Int) {
        let strip: (String) -> [Character] = { text in
            Array(text.filter { !$0.isWhitespace && !$0.isPunctuation })
        }
        let ref = strip(reference)
        let hyp = strip(hypothesis)
        return (editDistance(ref, hyp), ref.count)
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
