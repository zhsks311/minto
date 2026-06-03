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
        var emptyCount = 0
        // 전역 CER용: 모든 창의 hyp/ref를 이어붙인다. 창 경계를 가로지르는 매칭이
        // 허용돼, 자막 타이밍 드리프트로 구절이 옆 창으로 밀린 경우를 흡수한다.
        // (per-window micro-average는 그런 경우 양쪽 창을 모두 깎아 dissimilarity를 부풀린다.)
        var allRefText = ""
        var allHypText = ""
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
            if result.segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyCount += 1
            }
            allRefText += window.text + " "
            allHypText += result.segment.text + " "
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
        let globalStats = Self.cerStats(reference: allRefText, hypothesis: allHypText)
        let globalCER = globalStats.refLen > 0 ? Double(globalStats.distance) / Double(globalStats.refLen) : 0
        print("""
        ────────────────────────────────────────
        창 수             : \(windowCount) (빈 출력 \(emptyCount)개)
        per-window  CER   : \(String(format: "%.1f%%", microCER * 100)) (Σ편집거리 \(totalDistance) / 참조 \(totalRefLen)자)
        global(전체) CER  : \(String(format: "%.1f%%", globalCER * 100)) (전체 이어붙여 1회 정렬)  → 유사도 \(String(format: "%.1f%%", (1 - globalCER) * 100))
        ========================================
        ※ global이 per-window보다 낮으면 그 차이는 창 경계 드리프트(측정 아티팩트)다.
          방송 자막은 비verbatim이라 남는 CER에도 줄일 수 없는 바닥이 있다.

        """)

        // 측정 하니스이므로 회귀 게이트가 아닌 느슨한 sanity bound만 둔다.
        #expect(microCER < 0.80, "micro-CER sanity bound 초과: \(String(format: "%.1f%%", microCER * 100))")
    }

    /// 비발화/저신뢰 구간을 프로덕션 경로로 전사해 "환각 날조가 없는지" 점검한다(회귀 가드).
    /// 배경: logProbThreshold/avgLogprob 가드를 풀어 빈 출력을 강제 복구하려던 2-pass 시도는
    /// 정회 웅성거림에서 "감사합니다" phantom, 한국어 클립에서 영어를 날조해 폐기했다(빈 출력이
    /// 정직한 동작). 이 구간들은 모두 빈 출력이어야 한다 — 텍스트가 나오면 날조 회귀 신호.
    /// 실행: RUN_STT_TESTS=1 MEETING_SPAN_PROBE=1 swift test -c release --filter MeetingCorpusTests
    @Test("비발화 환각 회귀 가드")
    func nonSpeechFabricationProbe() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1",
              ProcessInfo.processInfo.environment["MEETING_SPAN_PROBE"] == "1" else { return }
        guard FileManager.default.fileExists(atPath: Self.audioURL.path) else { return }

        let samples = try Self.readWAVSamples(from: Self.audioURL)
        let service = STTService()
        await service.loadModel(variant: Self.model)
        guard case .loaded = service.modelState else { Issue.record("모델 로드 실패"); return }

        // haengan_20260526 기준. 모두 빈 출력이 정상(발화-빈출력 클립도 단일 패스에선 비어야 정상).
        let spans: [(String, Double, Double)] = [
            ("정회 한복판(비발화 -45dB)", 120, 180),
            ("정회 끝(비발화 -24.8dB)", 180, 187),
            ("저신뢰 발화#1", 96.8, 104.4),
            ("저신뢰 발화#2", 330.2, 333.2),
        ]
        print("\n=== 비발화 환각 회귀 가드 (프로덕션 경로) ===")
        for (label, start, end) in spans {
            let s = max(0, Int(start * Double(Self.sampleRate)))
            let e = min(samples.count, Int(end * Double(Self.sampleRate)))
            guard e > s else { continue }
            let text = try await service.transcribe(pcmSamples: Array(samples[s..<e])).segment.text
            print("[Probe] \(label) [\(start)-\(end)] → \(text.isEmpty ? "(빈 출력 ✓)" : "'\(text.prefix(90))' ⚠️ 날조?")")
        }
    }

    /// LLM 후교정 레이어가 전사 품질에 실제로 기여하는지 측정한다(raw vs 교정후 global CER 델타).
    ///
    /// 신뢰성의 전제(advisor): **창마다 STT는 한 번만 돌리고 그 raw를 그대로 교정에 넣는다.**
    /// 그래야 ANE 비결정성(±8pp)·방송자막 비verbatim 바닥(~40%)이 raw·corrected 양쪽에 똑같이
    /// 박혀 *델타에서 상쇄*된다. 재전사하면 상쇄가 깨져 절대 CER만큼 무의미해진다.
    ///
    /// 함정(T7 재발 주의): 교정 LLM이 없던 내용을 그럴듯하게 *추가(insertion)*하면 verbose한
    /// 자막과 우연히 맞아 CER이 거짓으로 내려갈 수 있다. 그래서 델타 숫자만 보지 않고
    /// touch rate(교정이 실제로 바꾼 정도)와 길이 증가·변경 diff를 함께 찍어 "수정"인지
    /// "추가"인지 눈으로 확인한다.
    ///
    /// 해석 비대칭: CER↓ = 진짜 이득. 평평/소폭↑ = 애매(보수 corrector는 실제 발화에 가까워질수록
    /// 패러프레이즈된 자막과 멀어져 이득이 구조적으로 과소계상됨). touch rate가 낮은데 델타≈0이면
    /// "교정 무용"이 아니라 "여기선 안전하게 무해"로 읽는다.
    ///
    /// 실행: RUN_STT_TESTS=1 RUN_CORRECTION_TEST=1 swift test -c release \
    ///       --filter MeetingCorpusTests/correctionContributionCER
    ///   (Codex Pro 주력 — Gemini는 429. 앱에서 Codex 로그인 선행 필요. env로 창 수·맥락 조절:
    ///    MEETING_CORR_WINDOWS=25, MEETING_TOPIC, MEETING_GLOSSARY(줄 단위))
    @Test("회의 코퍼스 교정 레이어 기여도 (raw vs Codex 교정 CER 델타)")
    func correctionContributionCER() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1",
              ProcessInfo.processInfo.environment["RUN_CORRECTION_TEST"] == "1" else { return }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: Self.audioURL.path),
              fileManager.fileExists(atPath: Self.smiURL.path) else {
            print("[Meeting] 자료 없음 — skip")
            return
        }
        guard CodexOAuthService.shared.isLoggedIn else {
            Issue.record("Codex 미로그인 — 앱에서 먼저 로그인 필요")
            return
        }

        // 비용 보호: 교정은 API 호출이라 기본 25창만(일반 측정 60창과 별도 env).
        let corrWindows = ProcessInfo.processInfo.environment["MEETING_CORR_WINDOWS"].flatMap(Int.init) ?? 25
        // 회의 맥락(행안위 기본, env override). 고정값은 절차·부처 용어만 — 특정 발언/이름을 날조하지 않는다.
        let topic = ProcessInfo.processInfo.environment["MEETING_TOPIC"]
            ?? "국회 행정안전위원회 전체회의 (행정안전부 소관 안건 심사·질의)"
        let glossary = ProcessInfo.processInfo.environment["MEETING_GLOSSARY"]
            ?? "행정안전부\n위원장\n간사\n의사일정\n안건\n정회\n속개\n의결\n출석"

        let captions = try Self.parseSMI(from: Self.smiURL)
        let windows = Self.mergeIntoWindows(captions, windowSeconds: Self.windowSeconds)
        let targetWindows = Array(windows.prefix(corrWindows))
        guard !targetWindows.isEmpty else { Issue.record("병합된 창이 없습니다"); return }

        let samples = try Self.readWAVSamples(from: Self.audioURL)
        let service = STTService()
        await service.loadModel(variant: Self.model)
        guard case .loaded = service.modelState else { Issue.record("모델 로드 실패: \(service.modelState)"); return }

        print("\n=== 교정 기여도 측정 [\(Self.model) → Codex] (window=\(Self.windowSeconds)s, \(targetWindows.count)/\(windows.count)창) ===")

        var allRefText = ""
        var allRawText = ""
        var allCorrText = ""
        var allCorrCleanText = ""   // 탈오염본: 추가 의심(insertion) 창은 교정 대신 raw로 되돌려 누적
        var nonEmptyWindows = 0     // 교정 대상이 된 비어있지 않은 raw 창
        var touchedWindows = 0      // 교정이 실제로 글자를 바꾼 창
        var touchDistance = 0       // Σ editDistance(raw, corrected) — 변경의 총량
        var touchedRawLen = 0       // 변경된 창의 raw 글자수(touch rate 분모)
        var fallbackCount = 0       // 교정 API 실패로 raw를 그대로 쓴 창(델타를 조용히 0으로 만드는 원인 → 명시 집계)
        var insertionFlags = 0      // 교정본이 raw보다 크게 길어진 창(추가=게이밍 의심)
        var prevRaw = ""            // 직전 발화 맥락(프로덕션과 동일하게 이전 창 raw를 넘김)

        for (index, window) in targetWindows.enumerated() {
            let startSample = max(0, Int(window.start * Double(Self.sampleRate)))
            let endSample = min(samples.count, Int(window.end * Double(Self.sampleRate)))
            guard endSample > startSample else { continue }

            // STT는 창당 1회만. 이 raw를 교정 입력으로 재사용해야 델타에서 노이즈가 상쇄된다.
            let raw = try await service.transcribe(pcmSamples: Array(samples[startSample..<endSample])).segment.text
            var corrected = raw
            var isInsertion = false

            if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nonEmptyWindows += 1
                let prompt = CorrectionPrompt.build(topic: topic, glossary: glossary, context: prevRaw, text: raw)
                do {
                    corrected = try await CodexOAuthService.shared.correct(instructions: prompt.instructions, userContent: prompt.userContent)
                } catch {
                    fallbackCount += 1
                    corrected = raw  // 폴백(=델타 기여 0). 무용이 아니라 "측정 못한 창"으로 따로 센다.
                    print("[Corr] #\(index) 교정 실패(폴백): \(error.localizedDescription)")
                }
                if corrected != raw {
                    let stats = Self.cerStats(reference: raw, hypothesis: corrected)
                    touchedWindows += 1
                    touchDistance += stats.distance
                    touchedRawLen += stats.refLen
                    let rawLen = Self.strippedCount(raw)
                    let corrLen = Self.strippedCount(corrected)
                    // 교정본이 raw보다 20%+ 길면 "수정"이 아니라 "추가" 의심(T7식 CER 게이밍 신호).
                    if rawLen > 0, Double(corrLen) > Double(rawLen) * 1.2 {
                        insertionFlags += 1
                        isInsertion = true
                    }
                    print("[Corr] #\(index) (raw \(rawLen)→corr \(corrLen)자, 편집 \(stats.distance))\(isInsertion ? " ⚠️추가의심" : "")")
                    print("    RAW : \(raw.prefix(120))")
                    print("    CORR: \(corrected.prefix(120))")
                }
            }

            allRefText += window.text + " "
            allRawText += raw + " "
            allCorrText += corrected + " "
            // 탈오염본: 추가 의심 창은 교정의 날조가 CER을 거짓으로 흔들므로 raw로 되돌려 누적.
            allCorrCleanText += (isInsertion ? raw : corrected) + " "
            prevRaw = raw
        }

        let rawStats = Self.cerStats(reference: allRefText, hypothesis: allRawText)
        let corrStats = Self.cerStats(reference: allRefText, hypothesis: allCorrText)
        let cleanStats = Self.cerStats(reference: allRefText, hypothesis: allCorrCleanText)
        let rawCER = rawStats.refLen > 0 ? Double(rawStats.distance) / Double(rawStats.refLen) : 0
        let corrCER = corrStats.refLen > 0 ? Double(corrStats.distance) / Double(corrStats.refLen) : 0
        let cleanCER = cleanStats.refLen > 0 ? Double(cleanStats.distance) / Double(cleanStats.refLen) : 0
        let deltaPP = (corrCER - rawCER) * 100        // 음수 = 개선 (날조 포함)
        let cleanDeltaPP = (cleanCER - rawCER) * 100  // 음수 = 개선 (추가 의심 창 제외한 substantive 이득)
        let touchRate = touchedRawLen > 0 ? Double(touchDistance) / Double(touchedRawLen) : 0

        // verdict는 자신의 insertion 신호를 무시하면 안 된다(추가가 있는데 "진짜 이득"을 찍는 T7식 자기기만 방지).
        // substantive 이득 판정은 날조를 뺀 cleanDelta로 한다.
        let verdict: String
        if insertionFlags > 0 {
            verdict = "⚠️ 추가 의심 \(insertionFlags)창(날조 가능) — raw 델타 \(String(format: "%+.1fpp", deltaPP))엔 거짓 이득 섞임. 날조 제외 델타 \(String(format: "%+.1fpp", cleanDeltaPP))가 substantive 판정값."
        } else if cleanDeltaPP < -1.0 {
            verdict = "교정이 자막 기준 CER을 낮춤 → 진짜 이득(추가 없음, touch rate로 확인)"
        } else if cleanDeltaPP > 1.0 {
            verdict = "교정 후 CER 상승 → ⚠️ 과교정 또는 자막과의 거리 증가. diff 확인 필수"
        } else {
            verdict = "델타≈0 → 애매: touch rate 낮으면 '무해', 높으면 '자막 비verbatim에 가려진 이득' 가능"
        }

        print("""
        ────────────────────────────────────────
        창 수            : \(targetWindows.count) (비어있지 않은 raw \(nonEmptyWindows), 교정이 바꾼 창 \(touchedWindows), 폴백 \(fallbackCount))
        global raw  CER  : \(String(format: "%.1f%%", rawCER * 100))
        global corr CER  : \(String(format: "%.1f%%", corrCER * 100))
        델타(corr-raw)   : \(String(format: "%+.1fpp", deltaPP)) (음수=개선, 날조 포함)
        ── 날조 탈오염(추가 의심 \(insertionFlags)창을 raw로 되돌림) ──
        global clean CER : \(String(format: "%.1f%%", cleanCER * 100))
        델타(clean-raw)  : \(String(format: "%+.1fpp", cleanDeltaPP)) (음수=개선, substantive 이득)
        touch rate       : \(String(format: "%.1f%%", touchRate * 100)) (변경 창 raw 대비 편집 비율)
        ========================================
        해석: \(verdict)
        ※ 폴백 \(fallbackCount)창은 corrected=raw라 델타에 0 기여 — 교정 효과가 아니라 측정 누락이다.
          절대 CER은 무시. raw→corr 델타만 신뢰(같은 raw를 공유해 노이즈 상쇄).

        """)
    }

    /// 공백·문장부호 제거 후 글자 수(insertion 판정용).
    private static func strippedCount(_ text: String) -> Int {
        text.filter { !$0.isWhitespace && !$0.isPunctuation }.count
    }

    /// 요약-as-context가 교정 품질에 주는 효과를 측정한다(항목1).
    /// 깨끗한 A/B: 창마다 raw를 1회 전사 → 같은 raw를 (요약 없이) vs (누적 요약 context로) 교정 →
    /// 두 corrected의 자막 global CER 델타. 같은 raw를 공유하므로 ANE 노이즈·자막 바닥이 상쇄되고
    /// 델타 = 요약 context의 순효과. Codex(uncapped)로 측정해 max_tokens와 무관.
    /// 실행: RUN_STT_TESTS=1 RUN_CORRECTION_TEST=1 RUN_SUMMARY_TEST=1 swift test -c release \
    ///       --filter MeetingCorpusTests/summaryContextContributionCER
    @Test("요약-as-context 교정 기여 측정 (요약 유무 A/B)")
    func summaryContextContributionCER() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1",
              ProcessInfo.processInfo.environment["RUN_CORRECTION_TEST"] == "1",
              ProcessInfo.processInfo.environment["RUN_SUMMARY_TEST"] == "1" else { return }
        guard FileManager.default.fileExists(atPath: Self.audioURL.path),
              FileManager.default.fileExists(atPath: Self.smiURL.path) else { return }
        guard CodexOAuthService.shared.isLoggedIn else { Issue.record("Codex 미로그인"); return }

        let savedProvider = LLMCorrectionService.shared.selectedProvider
        LLMCorrectionService.shared.selectedProvider = .codex
        defer { LLMCorrectionService.shared.selectedProvider = savedProvider }
        let topic = "국회 행정안전위원회 전체회의 (행정안전부 소관 안건 심사·질의)"
        let glossary = "행정안전부\n위원장\n간사\n의사일정\n안건\n정회\n속개"
        MeetingContext.shared.start(topic: topic, glossary: glossary)  // runningSummary 리셋됨
        defer { MeetingContext.shared.clear() }

        let corrWindows = ProcessInfo.processInfo.environment["MEETING_CORR_WINDOWS"].flatMap(Int.init) ?? 15
        let captions = try Self.parseSMI(from: Self.smiURL)
        let windows = Array(Self.mergeIntoWindows(captions, windowSeconds: Self.windowSeconds).prefix(corrWindows))
        let samples = try Self.readWAVSamples(from: Self.audioURL)

        let service = STTService()
        await service.loadModel(variant: Self.model)
        guard case .loaded = service.modelState else { Issue.record("모델 로드 실패"); return }

        print("\n=== 요약-as-context 교정 기여 측정 (\(windows.count)창, Codex) ===")
        var allRef = "", allNoSummary = "", allWithSummary = ""
        var prevContext = ""
        var changedBySummary = 0   // 요약 유무로 교정 결과가 달라진 창 수
        for (index, window) in windows.enumerated() {
            let s = max(0, Int(window.start * Double(Self.sampleRate)))
            let e = min(samples.count, Int(window.end * Double(Self.sampleRate)))
            guard e > s else { continue }
            let raw = try await service.transcribe(pcmSamples: Array(samples[s..<e])).segment.text
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                allRef += window.text + " "; allNoSummary += " "; allWithSummary += " "
                continue
            }
            let summarySoFar = MeetingContext.shared.runningSummary   // 직전 창들까지 반영
            // 같은 raw로 요약 없이 / 요약 context로 교정 (동일 직전맥락).
            let p0 = CorrectionPrompt.build(topic: topic, glossary: glossary, context: prevContext, text: raw, summary: "")
            let p1 = CorrectionPrompt.build(topic: topic, glossary: glossary, context: prevContext, text: raw, summary: summarySoFar)
            let corr0 = (try? await CodexOAuthService.shared.correct(instructions: p0.instructions, userContent: p0.userContent)) ?? raw
            let corr1 = (try? await CodexOAuthService.shared.correct(instructions: p1.instructions, userContent: p1.userContent)) ?? raw
            if corr0 != corr1 { changedBySummary += 1 }
            allRef += window.text + " "
            allNoSummary += corr0 + " "
            allWithSummary += corr1 + " "
            prevContext = corr1
            // 이 창을 누적 요약에 반영(다음 창의 summarySoFar에 들어감).
            _ = await SummaryService.shared.generateIncremental(correctedBatch: corr1)
        }

        let noSumCER = Double(Self.cerStats(reference: allRef, hypothesis: allNoSummary).distance) / Double(max(1, Self.cerStats(reference: allRef, hypothesis: allNoSummary).refLen))
        let withSumCER = Double(Self.cerStats(reference: allRef, hypothesis: allWithSummary).distance) / Double(max(1, Self.cerStats(reference: allRef, hypothesis: allWithSummary).refLen))
        let deltaPP = (withSumCER - noSumCER) * 100
        print("""
        ────────────────────────────────────────
        창 수                  : \(windows.count) (요약으로 결과 달라진 창 \(changedBySummary))
        global CER (요약 없이)  : \(String(format: "%.1f%%", noSumCER * 100))
        global CER (요약 context): \(String(format: "%.1f%%", withSumCER * 100))
        델타(요약 - 무요약)     : \(String(format: "%+.1fpp", deltaPP)) (음수=요약이 교정 개선)
        ========================================
        ※ 같은 raw 공유라 노이즈 상쇄 — 델타가 요약 context의 순효과. 절대값 무시.
          changedBySummary가 0이면 요약이 교정에 영향을 안 준 것(이 코퍼스 구간 한정).

        """)
    }

    /// 회의 요약 기능 end-to-end 스모크: 실제 코퍼스 구간을 증분 요약 → 최종 요약까지 돌려
    /// 요약이 (1) 생성되는지 (2) 전사에 없는 내용을 날조하지 않는지 눈으로 점검한다.
    /// 측정이 아니라 동작·날조 점검용이므로 결과를 print하고 생성 성공만 확인한다.
    /// 실행: RUN_STT_TESTS=1 RUN_CORRECTION_TEST=1 RUN_SUMMARY_TEST=1 swift test -c release \
    ///       --filter MeetingCorpusTests/summaryEndToEndProbe
    @Test("회의 요약 end-to-end 스모크 (Codex)")
    func summaryEndToEndProbe() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1",
              ProcessInfo.processInfo.environment["RUN_CORRECTION_TEST"] == "1",
              ProcessInfo.processInfo.environment["RUN_SUMMARY_TEST"] == "1" else { return }
        guard FileManager.default.fileExists(atPath: Self.audioURL.path),
              FileManager.default.fileExists(atPath: Self.smiURL.path) else { return }
        guard CodexOAuthService.shared.isLoggedIn else {
            Issue.record("Codex 미로그인"); return
        }

        // provider/맥락 세팅 — 테스트 후 provider 원복.
        let savedProvider = LLMCorrectionService.shared.selectedProvider
        LLMCorrectionService.shared.selectedProvider = .codex
        defer { LLMCorrectionService.shared.selectedProvider = savedProvider }
        MeetingContext.shared.start(topic: "국회 행정안전위원회 전체회의", glossary: "행정안전부\n위원장\n간사\n의사일정")
        MeetingContext.shared.runningSummary = ""
        MeetingContext.shared.finalSummary = ""
        defer { MeetingContext.shared.clear() }

        let captions = try Self.parseSMI(from: Self.smiURL)
        let windows = Self.mergeIntoWindows(captions, windowSeconds: Self.windowSeconds)
        let probeWindows = Array(windows.prefix(8))
        let samples = try Self.readWAVSamples(from: Self.audioURL)

        let service = STTService()
        await service.loadModel(variant: Self.model)
        guard case .loaded = service.modelState else { Issue.record("모델 로드 실패"); return }

        print("\n=== 회의 요약 end-to-end 스모크 (\(probeWindows.count)창) ===")
        for (index, window) in probeWindows.enumerated() {
            let s = max(0, Int(window.start * Double(Self.sampleRate)))
            let e = min(samples.count, Int(window.end * Double(Self.sampleRate)))
            guard e > s else { continue }
            let raw = try await service.transcribe(pcmSamples: Array(samples[s..<e])).segment.text
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            _ = await SummaryService.shared.generateIncremental(correctedBatch: raw)
            print("[Summary] #\(index) 후 누적 요약 길이=\(MeetingContext.shared.runningSummary.count)")
        }

        let final = await SummaryService.shared.generateFinal(tailText: "")
        print("""
        ──────────── 최종 요약 ────────────
        \(final ?? "(생성 실패)")
        ────────────────────────────────────
        ※ 위 요약이 전사에 없는 사실을 지어냈는지 눈으로 점검(날조 회귀 가드).
        """)
        #expect(final != nil, "요약이 생성되어야 한다")
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
