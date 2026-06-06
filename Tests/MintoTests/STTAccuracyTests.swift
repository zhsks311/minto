import Testing
@testable import MintoCore
import Foundation

/// 한국어 TTS round-trip 정확도 테스트.
/// 실행: RUN_STT_TESTS=1 swift test -c release --filter STTAccuracyTests
@MainActor
@Suite("STT Accuracy Tests (Manual Only)", .serialized)
struct STTAccuracyTests {

    private static let model = "openai_whisper-large-v3-v20240930_turbo"

    private static let testPhrases: [String] = [
        // 기본 인사·상황
        "안녕하세요 레코딩 테스트 중입니다",
        "잘 되고 있는지 확인하고 있습니다",
        "그런데 뭔가 생각하는 것 같아요",
        "오늘 날씨가 정말 좋네요",
        "회의 내용을 기록하고 있습니다",

        // 회의·업무 맥락
        "이번 분기 목표는 매출 20% 성장입니다",
        "다음 주 월요일까지 보고서를 제출해 주세요",
        "지난번에 논의했던 아키텍처 개선안에 대해 말씀드리겠습니다",
        "마케팅팀과 개발팀이 협업해서 진행하면 좋을 것 같습니다",
        "오늘 회의에서 결정된 사항을 정리해 드리겠습니다",

        // 긴 문장
        "사용자 인터페이스를 개선하고 성능을 최적화하기 위해 여러 가지 방법을 검토하고 있습니다",
        "이 기능은 실시간으로 음성을 텍스트로 변환하는 기술을 활용하고 있습니다",

        // 숫자·날짜
        "회의는 오후 2시에 시작해서 4시에 끝날 예정입니다",
        "총 예산은 3천만원으로 책정되어 있습니다",

        // 구어체·짧은 발화
        "네 맞아요 저도 그렇게 생각해요",
        "잠깐만요 다시 한번 말씀해 주시겠어요",
        "좋습니다 그렇게 진행하도록 하겠습니다",
    ]

    @Test("한국어 TTS round-trip CER 측정")
    func koreanTTSAccuracy() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1" else { return }

        let service = STTService()
        await service.loadModel(variant: Self.model)
        guard case .loaded = service.modelState else {
            Issue.record("모델 로드 실패: \(service.modelState)")
            return
        }

        var results: [(ref: String, hyp: String, cer: Double)] = []
        for phrase in Self.testPhrases {
            let samples = try generateTTSPCM(text: phrase)
            let result = try await service.transcribe(pcmSamples: samples)
            let cer = characterErrorRate(reference: phrase, hypothesis: result.segment.text)
            results.append((ref: phrase, hyp: result.segment.text, cer: cer))
        }

        let avgCER = results.map(\.cer).reduce(0, +) / Double(results.count)

        print("\n=== STT 정확도 보고서 [\(Self.model)] ===")
        for r in results {
            let acc = Int((1 - r.cer) * 100)
            print("[\(String(format: "%3d", acc))%] 기대: \(r.ref)")
            print("       결과: \(r.hyp)")
        }
        print("────────────────────────────────────────")
        print("평균 CER   : \(String(format: "%.1f%%", avgCER * 100))")
        print("평균 정확도: \(String(format: "%.1f%%", (1 - avgCER) * 100))")
        print("========================================\n")

        #expect(avgCER < 0.30, "평균 CER 30% 미만이어야 합니다. 실제: \(String(format: "%.1f%%", avgCER * 100))")
    }

    // MARK: - TTS → PCM 변환

    private func generateTTSPCM(text: String) throws -> [Float] {
        let tmp  = URL(fileURLWithPath: NSTemporaryDirectory())
        let aiff = tmp.appendingPathComponent("minto_tts.aiff")
        let wav  = tmp.appendingPathComponent("minto_tts.wav")

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Yuna", "-r", "160", text, "-o", aiff.path]
        try say.run(); say.waitUntilExit()

        let afconvert = Process()
        afconvert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        afconvert.arguments = ["-f", "WAVE", "-d", "LEF32@16000", "-c", "1", aiff.path, wav.path]
        try afconvert.run(); afconvert.waitUntilExit()

        return try readWAVSamples(from: wav)
    }

    private func readWAVSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        // "data" 청크 마커를 찾아 실제 샘플 시작 위치를 구함
        let dataMarker = Data([0x64, 0x61, 0x74, 0x61]) // "data"
        guard let markerRange = data.range(of: dataMarker) else {
            throw NSError(domain: "STTAccuracy", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "WAV data chunk not found"])
        }
        let sampleOffset = markerRange.upperBound + 4 // 청크 크기 필드 4바이트 skip
        guard data.count > sampleOffset else {
            throw NSError(domain: "STTAccuracy", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "WAV data too small"])
        }
        let sampleData = data.subdata(in: sampleOffset..<data.count)
        return sampleData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self))
        }
    }

    // MARK: - CER 측정

    private func characterErrorRate(reference: String, hypothesis: String) -> Double {
        // 구두점·공백을 제거한 뒤 비교 (Whisper는 마침표·쉼표를 자동 추가하므로 측정에서 제외)
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
