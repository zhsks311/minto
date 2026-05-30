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
            noSpeechThreshold: 0.90   // default 0.6 → 배경소음 환경에서 발화를 무음으로 잘못 판정 방지
        )

        let wkResults = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        var fullText = ""
        for result in wkResults {
            for seg in result.segments {
                // Whisper 자체 품질 지표 기반 필터 (OpenAI 원본 임계값)
                guard seg.noSpeechProb < 0.6 else {
                    fputs("[STT] skip: noSpeech=\(String(format:"%.2f", seg.noSpeechProb))\n", stderr)
                    continue
                }
                guard seg.avgLogprob > -1.0 else {
                    fputs("[STT] skip: avgLogprob=\(String(format:"%.2f", seg.avgLogprob))\n", stderr)
                    continue
                }
                guard seg.compressionRatio < 2.4 else {
                    fputs("[STT] skip: compressionRatio=\(String(format:"%.2f", seg.compressionRatio))\n", stderr)
                    continue
                }
                let text = Self.stripWhisperTokens(seg.text).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                // [MUSIC], [BLANK_AUDIO], (웃음) 등 Whisper 메타 태그
                guard !text.hasPrefix("["), !text.hasPrefix("(") else { continue }
                fullText += text
            }
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
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

}
