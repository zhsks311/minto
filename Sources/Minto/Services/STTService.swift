import Foundation
@preconcurrency import WhisperKit

/// WhisperKit 기반 STT 서비스.
/// @MainActor 격리: WhisperKit 자체가 내부 비동기를 처리하므로 메인 스레드를 블록하지 않음.
@MainActor
public final class STTService {

    // MARK: - Public state

    public private(set) var modelState: ModelState = .unloaded
    public private(set) var modelVariant: String = "openai_whisper-large-v3-v20240930_turbo"

    // ViewModel이 modelState 변화를 @Published 없이 수신하는 콜백
    var onModelStateChange: ((ModelState) -> Void)?

    // MARK: - Private

    nonisolated(unsafe) private var pipe: WhisperKit?

    public init() {}

    // MARK: - Model loading

    public func loadModel(variant: String = "openai_whisper-large-v3-v20240930_turbo") async {
        modelVariant = variant
        fputs("[STT] downloading \(variant)...\n", stderr)
        updateState(.downloading(0))

        do {
            let folder = try await WhisperKit.download(
                variant: variant,
                progressCallback: { @Sendable [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.updateState(.downloading(progress.fractionCompleted))
                    }
                }
            )
            fputs("[STT] initializing WhisperKit...\n", stderr)
            updateState(.loading)
            pipe = try await WhisperKit(WhisperKitConfig(
                model: variant,
                modelFolder: folder.path(percentEncoded: false)
            ))
            updateState(.loaded)
            fputs("[STT] WhisperKit ready: \(variant)\n", stderr)
        } catch {
            updateState(.failed(error.localizedDescription))
            fputs("[STT] load error: \(error)\n", stderr)
        }
    }

    // MARK: - Transcription

    public func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        guard let pipe else { throw STTError.modelNotLoaded }

        // whisper 최소 입력 ~0.5s @16kHz
        let minSamples = 8000
        let samples = pcmSamples.count < minSamples
            ? pcmSamples + [Float](repeating: 0, count: minSamples - pcmSamples.count)
            : pcmSamples

        // 에너지 사전 필터: RMS < -30dB 이면 배경 소음으로 간주해 Whisper 호출 생략
        let rms = sqrt(samples.reduce(0.0 as Float) { $0 + $1 * $1 } / Float(samples.count))
        let dbLevel = 20 * log10(max(rms, 1e-7))
        if dbLevel < -50 {
            fputs("[STT] skip (energy=\(String(format: "%.1f", dbLevel))dB)\n", stderr)
            let seg = Segment(text: "", timestamp: Date(), duration: Double(samples.count) / 16000.0)
            return TranscriptionResult(segment: seg, isFinal: true)
        }

        let options = DecodingOptions(
            language: "ko",
            wordTimestamps: false,
            // 윈도우 첫 토큰 위치에서 공백·EOT를 억제(OpenAI Whisper 기본값과 일치).
            // 발화가 있는 청크가 빈 출력으로 끝나는 경우를 줄인다. 첫 위치에만 적용되므로
            // 부작용은 최대 토큰 1개이며, 순수 무음 청크는 위 에너지 사전필터(-50dB)가
            // 이미 걸러 할루시네이션 위험이 낮다.
            suppressBlank: true,
            // supressTokens(비발화 토큰 억제)·windowClipTime은 기본값을 의도적으로 유지한다.
            // WhisperKit가 nonSpeechTokens 기본 구현을 하지 않아(TODO) 올바른 토큰 ID를 직접
            // 넣는 것은 모델/토크나이저 의존적이라 위험 > 이득. windowClipTime은 청크 내 seek
            // 동작이라 VAD로 청크를 직접 끊는 이 파이프라인엔 영향이 적다.
            noSpeechThreshold: 0.80   // g2 350샘플 실험: 0.80 최적 (CER 5.7%)
        )

        // 세그먼트에서 텍스트만 모은다.
        // - noSpeechProb 사후필터는 두지 않는다(의도): WhisperKit가 디코딩 시 noSpeechThreshold
        //   (0.80)로 무음을 이미 skip하고, avgLogProb가 logProbThreshold(-1.0)보다 높으면 "확신"이
        //   무음 판정을 덮어쓴다(SegmentSeeker). 0.6 재검은 그 튜닝을 무효화한다.
        // - avgLogprob/compressionRatio는 할루시네이션 가드. WhisperKit는 이 둘을 fallback 트리거로만
        //   쓰고(버리지 않음) best-effort를 반환하므로, 그 반복/환각 잔재를 앱이 최종 차단한다.
        // - recoveryMode면 avgLogprob 가드를 건너뛴다(저신뢰 복구 텍스트를 살리려고). 단 compressionRatio
        //   가드는 유지해 반복/영어 환각 루프는 계속 막는다.
        func extractText(decodeOptions: DecodingOptions, recoveryMode: Bool) async throws -> String {
            let wkResults = try await pipe.transcribe(audioArray: samples, decodeOptions: decodeOptions)
            var fullText = ""
            for result in wkResults {
                for seg in result.segments {
                    if !recoveryMode {
                        guard seg.avgLogprob > -1.0 else {
                            fputs("[STT] skip: avgLogprob=\(String(format:"%.2f", seg.avgLogprob))\n", stderr)
                            continue
                        }
                    }
                    guard seg.compressionRatio < 2.4 else {
                        fputs("[STT] skip: compressionRatio=\(String(format:"%.2f", seg.compressionRatio))\n", stderr)
                        continue
                    }
                    let text = Self.stripWhisperTokens(seg.text).trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { continue }
                    // [MUSIC], [BLANK_AUDIO], (웃음) 등 Whisper 메타 태그
                    guard !text.hasPrefix("["), !text.hasPrefix("(") else { continue }
                    guard !Self.isKnownHallucination(text) else { continue }
                    fullText += text
                }
            }
            return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmed = try await extractText(decodeOptions: options, recoveryMode: false)

        // 빈 출력 복구(2-pass). 진단: 저신뢰 발화 클립은 logProbThreshold(-1.0)가 결과를 "실패"로
        // 플래그 → temperature가 1.0까지 fallback → 모델이 즉시 <|endoftext|>를 뱉어 빈 출력이 된다
        // (RMS는 정상 발화 수준, 무음 아님). 빈 출력일 때만 logProbThreshold를 꺼 한 번 더 디코딩하면
        // 저신뢰라도 부분 텍스트를 건진다(CER상 빈 출력 100%보다 낫다). 깨끗한 발화는 1패스에서 비지
        // 않으므로 이 경로를 타지 않아 품질 회귀가 없다.
        if trimmed.isEmpty {
            let recoveryOptions = DecodingOptions(
                language: "ko",
                wordTimestamps: false,
                suppressBlank: true,
                logProbThreshold: nil,   // 저신뢰 결과를 fallback으로 버리지 않음
                noSpeechThreshold: 0.80
            )
            let recovered = try await extractText(decodeOptions: recoveryOptions, recoveryMode: true)
            if !recovered.isEmpty {
                fputs("[STT] recovered empty output via logProb-relaxed retry (\(recovered.count) chars)\n", stderr)
                trimmed = recovered
            }
        }

        let segment = Segment(
            text: trimmed,
            timestamp: Date(),
            duration: Double(samples.count) / 16000.0
        )
        return TranscriptionResult(segment: segment, isFinal: true)
    }

    // MARK: - Private helpers

    private func updateState(_ state: ModelState) {
        modelState = state
        onModelStateChange?(state)
    }

    /// meeting-transcriber에서 채용: WhisperKit 특수 토큰 제거
    private static func stripWhisperTokens(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<\|[^|]*\|>"#,
            with: "",
            options: .regularExpression
        )
    }

    /// 모델 메트릭으로 잡히지 않는 확정 할루시네이션
    private static func isKnownHallucination(_ text: String) -> Bool {
        // 현재는 모델 메트릭(noSpeechProb, avgLogprob, compressionRatio)에 위임
        // 텍스트 기반 필터는 실제 발화를 오필터링할 수 있어 사용하지 않음
        return false
    }

}
