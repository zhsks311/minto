import os
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

@MainActor
final class SpeechAnalyzerSTTEngine: SpeechTranscriptionEngine {
    let engineID: SpeechEngineID = .speechAnalyzer
    let modelVariant: String = SpeechEngineID.speechAnalyzer.rawValue
    var supportsPreviewTranscription: Bool { false }

    func load(updateState: @escaping STTStateUpdater) async throws {
        let availability = await Self.availability()
        guard availability.isSelectable else {
            throw STTError.engineUnavailable(availability.detailText ?? "SpeechAnalyzer를 사용할 수 없어요.")
        }
        updateState(.loaded)
        Log.stt.info("Apple speech engine ready: \(self.engineID.rawValue, privacy: .public)")
    }

    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        guard #available(macOS 26.0, *) else {
            throw STTError.engineUnavailable("SpeechAnalyzer는 macOS 26 이상에서 사용할 수 있어요.")
        }

        let availability = await Self.availability()
        guard availability.isSelectable else {
            throw STTError.engineUnavailable(availability.detailText ?? "SpeechAnalyzer를 사용할 수 없어요.")
        }

        let samples = STTAudioUtilities.paddedSamples(pcmSamples)
        if let silent = STTAudioUtilities.silentResultIfNeeded(samples) {
            return silent
        }

        let url = try STTAudioUtilities.writeTemporaryAudioFile(samples: samples)
        defer { try? FileManager.default.removeItem(at: url) }

        let audioFile = try AVAudioFile(forReading: url)
        let transcriber = SpeechTranscriber(locale: STTAudioUtilities.koreanLocale, preset: .transcription)
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: options)

        let resultTask = Task<String, Error> {
            var fullText = ""
            var latestText = ""
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if result.isFinal {
                    fullText += text
                } else {
                    latestText = text
                }
            }
            return fullText.isEmpty ? latestText : fullText
        }

        do {
            let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile)
            if let lastSampleTime {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        let text = try await resultTask.value
        return STTAudioUtilities.transcriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sampleCount: samples.count
        )
    }

    static func availability() async -> SpeechEngineAvailability {
        guard #available(macOS 26.0, *) else {
            return .unavailable("macOS 26 이상에서 사용할 수 있어요.")
        }

        guard SpeechTranscriber.isAvailable else {
            return .unavailable("현재 기기에서 SpeechAnalyzer를 사용할 수 없어요.")
        }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: STTAudioUtilities.koreanLocale) else {
            return .unavailable("한국어 SpeechAnalyzer 지원을 찾을 수 없어요.")
        }

        let installedLocales = await SpeechTranscriber.installedLocales
        guard installedLocales.contains(where: { $0.identifier == locale.identifier }) else {
            return .unavailable("한국어 SpeechAnalyzer asset이 설치되어 있지 않아요.")
        }

        return .available
    }
}
