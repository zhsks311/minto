import os
import Foundation
@preconcurrency import WhisperKit

@MainActor
final class WhisperKitSTTEngine: SpeechTranscriptionEngine {
    let engineID: SpeechEngineID
    let modelVariant: String
    var supportsPreviewTranscription: Bool { true }

    nonisolated(unsafe) private var pipe: WhisperKit?

    init(variant: String) {
        self.modelVariant = variant
        self.engineID = SpeechEngineID.fromWhisperVariant(variant)
    }

    func load(updateState: @escaping STTStateUpdater) async throws {
        let folder: URL
        if let localFolder = Self.localModelFolderOverride() {
            folder = localFolder
            Log.stt.info("initializing WhisperKit from local folder: \(folder.lastPathComponent, privacy: .public)")
            updateState(.loading)
        } else {
            Log.stt.info("downloading \(self.modelVariant, privacy: .public)")
            updateState(.downloading(0))
            folder = try await WhisperKit.download(
                variant: modelVariant,
                progressCallback: { @Sendable progress in
                    Task { @MainActor in
                        updateState(.downloading(progress.fractionCompleted))
                    }
                }
            )
        }

        Log.stt.info("initializing WhisperKit")
        updateState(.loading)
        pipe = try await WhisperKit(WhisperKitConfig(
            model: modelVariant,
            modelFolder: folder.path(percentEncoded: false)
        ))
        updateState(.loaded)
        Log.stt.info("WhisperKit ready: \(self.modelVariant, privacy: .public)")
    }

    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        guard let pipe else { throw STTError.modelNotLoaded }

        let samples = STTAudioUtilities.paddedSamples(pcmSamples)
        let dbLevel = STTAudioUtilities.dbLevel(samples)
        if dbLevel < -50 {
            Log.stt.debug("skip energy=\(String(format: "%.1f", dbLevel), privacy: .public)dB")
            let seg = Segment(text: "", timestamp: Date(), duration: Double(samples.count) / STTAudioUtilities.sampleRate)
            return TranscriptionResult(segment: seg, isFinal: true)
        }

        let options = DecodingOptions(
            language: "ko",
            wordTimestamps: false,
            // 윈도우 첫 토큰 위치에서 공백·EOT를 억제(OpenAI Whisper 기본값과 일치).
            // 발화가 있는 청크가 빈 출력으로 끝나는 경우를 줄인다.
            suppressBlank: true,
            // supressTokens(비발화 토큰 억제)·windowClipTime은 기본값을 의도적으로 유지한다.
            // WhisperKit가 nonSpeechTokens 기본 구현을 하지 않아(TODO) 올바른 토큰 ID를 직접
            // 넣는 것은 모델/토크나이저 의존적이라 위험 > 이득.
            noSpeechThreshold: 0.80
        )

        let wkResults = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        var fullText = ""
        for result in wkResults {
            for seg in result.segments {
                guard seg.avgLogprob > -1.0 else {
                    Log.stt.debug("skip avgLogprob=\(String(format:"%.2f", seg.avgLogprob), privacy: .public)")
                    continue
                }
                guard seg.compressionRatio < 2.4 else {
                    Log.stt.debug("skip compressionRatio=\(String(format:"%.2f", seg.compressionRatio), privacy: .public)")
                    continue
                }
                let text = Self.stripWhisperTokens(seg.text).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                guard !text.hasPrefix("["), !text.hasPrefix("(") else { continue }
                guard !Self.isKnownHallucination(text) else { continue }
                fullText += text
            }
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if dbLevel < -40, !trimmed.isEmpty, trimmed.count <= 10 {
            Log.stt.debug("skip low-energy short phantom \(String(format:"%.1f", dbLevel), privacy: .public)dB chars=\(trimmed.count, privacy: .public)")
            let seg = Segment(text: "", timestamp: Date(), duration: Double(samples.count) / STTAudioUtilities.sampleRate)
            return TranscriptionResult(segment: seg, isFinal: true)
        }

        let segment = Segment(
            text: trimmed,
            timestamp: Date(),
            duration: Double(samples.count) / STTAudioUtilities.sampleRate
        )
        return TranscriptionResult(segment: segment, isFinal: true)
    }

    nonisolated static func localModelFolderOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let value = environment["WHISPER_MODEL_FOLDER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: value)
    }

    private static func stripWhisperTokens(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<\|[^|]*\|>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func isKnownHallucination(_ text: String) -> Bool {
        false
    }
}
