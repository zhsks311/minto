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

        let p = CorrectionPrompt.build(topic: "", glossary: "", context: "", text: raw)
        let corrected = try await CodexOAuthService.shared.correct(instructions: p.instructions, userContent: p.userContent)
        print("""

=== Codex 교정 비교 ===
원본  : \(raw)
교정본: \(corrected)
=======================
""")

        #expect(!corrected.isEmpty, "교정본이 비어있지 않아야 합니다")
    }

    @Test("Gemini loadCodeAssist 원본 응답 확인 (project/tier 진단)")
    func geminiLoadCodeAssistProbe() async throws {
        guard ProcessInfo.processInfo.environment["RUN_CORRECTION_TEST"] == "1" else { return }
        guard GeminiOAuthService.shared.isLoggedIn else {
            Issue.record("Gemini 미로그인")
            return
        }

        let token = try await GeminiOAuthService.shared.validAccessToken()
        let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // gemini-cli가 보내는 metadata 형태로 요청
        let body: [String: Any] = [
            "metadata": ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        print("""

=== loadCodeAssist HTTP \(status) ===
\(raw)
=====================================
""")
    }

    @Test("sample 첫 청크 전사 → Gemini 교정 비교")
    func transcribeThenCorrectGemini() async throws {
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

        let allSamples = try await extractPCM(from: mp4URL)
        let chunkSize = 16000 * 30
        let firstChunk = Array(allSamples[0..<min(chunkSize, allSamples.count)])
        let raw = try await service.transcribe(pcmSamples: firstChunk).segment.text
        print("[CorrectionTest] 원본 전사:\n\(raw)")

        guard GeminiOAuthService.shared.isLoggedIn else {
            Issue.record("Gemini 미로그인 — 앱에서 먼저 로그인 필요")
            return
        }

        let p = CorrectionPrompt.build(topic: "", glossary: "", context: "", text: raw)
        let corrected = try await GeminiOAuthService.shared.correct(instructions: p.instructions, userContent: p.userContent)
        print("""

=== Gemini 교정 비교 ===
원본  : \(raw)
교정본: \(corrected)
========================
""")

        #expect(!corrected.isEmpty, "교정본이 비어있지 않아야 합니다")
    }

    @Test("교정 품질 정량 비교: raw vs Codex vs Gemini (CER)")
    func correctionQualityComparison() async throws {
        guard ProcessInfo.processInfo.environment["RUN_CORRECTION_TEST"] == "1" else { return }

        let mp4URL = Self.sampleDir.appendingPathComponent("you/audio/test.mp4")
        let scriptURL = Self.sampleDir.appendingPathComponent("you/script/test.transcription.txt")
        guard FileManager.default.fileExists(atPath: mp4URL.path) else {
            Issue.record("test.mp4 없음: \(mp4URL.path)")
            return
        }
        guard CodexOAuthService.shared.isLoggedIn, GeminiOAuthService.shared.isLoggedIn else {
            Issue.record("Codex/Gemini 둘 다 로그인 필요")
            return
        }

        let reference = try parseScriptText(from: scriptURL)

        let service = STTService()
        await service.loadModel(variant: "openai_whisper-large-v3-v20240930_turbo")
        guard case .loaded = service.modelState else {
            Issue.record("모델 로드 실패: \(service.modelState)")
            return
        }

        let allSamples = try await extractPCM(from: mp4URL)
        let chunkSize = 16000 * 30
        let totalChunks = (allSamples.count + chunkSize - 1) / chunkSize
        // API 비용/시간 보호: 최대 12청크(6분)까지만 평가하고, 초과분은 명시적으로 알린다.
        let maxChunks = 12
        let evalChunks = min(totalChunks, maxChunks)
        if totalChunks > maxChunks {
            print("[QualityTest] ⚠️ 전체 \(totalChunks)청크 중 앞 \(maxChunks)청크만 평가 (나머지 \(totalChunks - maxChunks)청크 생략)")
        }

        var raw = "", codex = "", gemini = ""
        for idx in 0..<evalChunks {
            let start = idx * chunkSize
            let end = min(start + chunkSize, allSamples.count)
            let chunkText = try await service.transcribe(pcmSamples: Array(allSamples[start..<end])).segment.text
            if chunkText.isEmpty { continue }
            raw += chunkText + " "

            // 각 provider로 동일 청크 교정. 실패 시 원본 유지(실사용 동작과 동일).
            let p = CorrectionPrompt.build(topic: "", glossary: "", context: "", text: chunkText)
            let c = (try? await CodexOAuthService.shared.correct(instructions: p.instructions, userContent: p.userContent)) ?? chunkText
            let g = (try? await GeminiOAuthService.shared.correct(instructions: p.instructions, userContent: p.userContent)) ?? chunkText
            codex += c + " "
            gemini += g + " "
            print("[QualityTest] 청크 \(idx + 1)/\(evalChunks) 완료")
        }

        let report = """

        ===== 교정 품질 정량 비교 (\(evalChunks)청크) =====
        지표 1) 내용 CER  — 공백·문장부호 제거, 글자/동음이의어 정확도
        지표 2) 포맷 CER  — 공백·문장부호 포함, 가독성 일치도
        (낮을수록 reference에 가까움)

        [내용 CER]
          raw    : \(pct(characterErrorRate(reference: reference, hypothesis: raw)))
          Codex  : \(pct(characterErrorRate(reference: reference, hypothesis: codex)))
          Gemini : \(pct(characterErrorRate(reference: reference, hypothesis: gemini)))

        [포맷 CER]
          raw    : \(pct(formattedErrorRate(reference: reference, hypothesis: raw)))
          Codex  : \(pct(formattedErrorRate(reference: reference, hypothesis: codex)))
          Gemini : \(pct(formattedErrorRate(reference: reference, hypothesis: gemini)))
        =============================================
        """
        print(report)
    }

    private func pct(_ v: Double) -> String { String(format: "%.2f%%", v * 100) }

    /// 공백·문장부호를 유지한 채(런 공백만 단일화) 편집거리 기반 CER. 띄어쓰기·부호 개선을 반영한다.
    private func formattedErrorRate(reference: String, hypothesis: String) -> Double {
        let normalize: (String) -> [Character] = { s in
            let collapsed = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return Array(collapsed)
        }
        let ref = normalize(reference)
        let hyp = normalize(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    @Test("회의 맥락 유무 교정 비교 (Codex/Gemini)")
    func correctWithMeetingContext() async throws {
        guard ProcessInfo.processInfo.environment["RUN_CORRECTION_TEST"] == "1" else { return }

        let mp4URL = Self.sampleDir.appendingPathComponent("you/audio/test.mp4")
        guard FileManager.default.fileExists(atPath: mp4URL.path) else {
            Issue.record("test.mp4 없음: \(mp4URL.path)")
            return
        }
        guard CodexOAuthService.shared.isLoggedIn, GeminiOAuthService.shared.isLoggedIn else {
            Issue.record("Codex/Gemini 둘 다 로그인 필요")
            return
        }

        let service = STTService()
        await service.loadModel(variant: "openai_whisper-large-v3-v20240930_turbo")
        guard case .loaded = service.modelState else {
            Issue.record("모델 로드 실패: \(service.modelState)")
            return
        }

        let allSamples = try await extractPCM(from: mp4URL)
        let firstChunk = Array(allSamples[0..<min(16000 * 30, allSamples.count)])
        let raw = try await service.transcribe(pcmSamples: firstChunk).segment.text

        // 회의 맥락 (sample = 쿠팡 청문회 뉴스)
        let topic = "국회 쿠팡 물류센터 청문회 경제 뉴스 인터뷰"
        let glossary = "쿠팡\n청문회\n상임위\n불출석 사유서"

        let noCtx = CorrectionPrompt.build(topic: "", glossary: "", context: "", text: raw)
        let withCtx = CorrectionPrompt.build(topic: topic, glossary: glossary, context: "", text: raw)

        // 한 provider 실패(예: Gemini 429)가 나머지 결과를 가리지 않도록 각 호출을 독립적으로 감싼다.
        func tryCorrect(_ svc: @escaping () async throws -> String) async -> String {
            do { return try await svc() } catch { return "(실패: \(error.localizedDescription))" }
        }
        let codexNo = await tryCorrect { try await CodexOAuthService.shared.correct(instructions: noCtx.instructions, userContent: noCtx.userContent) }
        let codexCtx = await tryCorrect { try await CodexOAuthService.shared.correct(instructions: withCtx.instructions, userContent: withCtx.userContent) }
        let geminiNo = await tryCorrect { try await GeminiOAuthService.shared.correct(instructions: noCtx.instructions, userContent: noCtx.userContent) }
        let geminiCtx = await tryCorrect { try await GeminiOAuthService.shared.correct(instructions: withCtx.instructions, userContent: withCtx.userContent) }

        print("""

        ===== 회의 맥락 유무 교정 비교 =====
        [원본 전사]
        \(raw)

        [Codex · 맥락 없음]
        \(codexNo)

        [Codex · 맥락 있음]
        \(codexCtx)

        [Gemini · 맥락 없음]
        \(geminiNo)

        [Gemini · 맥락 있음]
        \(geminiCtx)
        ===================================
        """)
    }

    @Test("(b) 맥락-에코 차단: 짧은 입력에 직전 맥락을 출력에 토하지 않는다 (#8 회귀)")
    func contextEchoSuppression() async throws {
        guard ProcessInfo.processInfo.environment["RUN_CORRECTION_TEST"] == "1" else { return }
        guard CodexOAuthService.shared.isLoggedIn else { Issue.record("Codex 미로그인"); return }

        // #8 재현 시나리오: 직전 창이 "조용히 해 주십시오..."였고 현재 인식이 2자 "오늘"인 상황.
        // 과거 mini는 "오늘" → 직전 맥락 통째 에코로 회의록을 날조했다. (b) instructions("직전 맥락을
        // 출력에 옮겨 적지 마라")가 이를 막는지 확률적으로(3회) 확인한다.
        let context = "조용히 해 주십시오. 조용히 해 주십시오, 의원님들."
        let shortText = "오늘"
        let runs = 3
        var echoed = 0
        for i in 0..<runs {
            let p = CorrectionPrompt.build(topic: "국회 행정안전위원회", glossary: "", context: context, text: shortText)
            let corrected = (try? await CodexOAuthService.shared.correct(instructions: p.instructions, userContent: p.userContent)) ?? ""
            let echoedContext = corrected.contains("조용히 해 주십시오")
            let blewUp = corrected.count > shortText.count + 8   // 짧은 입력 대비 비정상 확장(에코 신호)
            if echoedContext || blewUp { echoed += 1 }
            print("[EchoProbe] run \(i + 1): '\(corrected)' (echo=\(echoedContext), len=\(corrected.count))")
        }
        print("[EchoProbe] \(runs)회 중 에코/확장 \(echoed)회")
        #expect(echoed == 0, "(b) 프롬프트가 맥락 에코를 막아야 함 — \(echoed)/\(runs)회 발생")
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
