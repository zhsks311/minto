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
            throw STTError.engineUnavailable(availability.detailText ?? "SpeechAnalyzer를 사용할 수 없습니다.")
        }
        updateState(.loaded)
        fputs("[STT] Apple speech engine ready: \(engineID.rawValue)\n", stderr)
    }

    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        guard #available(macOS 26.0, *) else {
            throw STTError.engineUnavailable("SpeechAnalyzer는 macOS 26 이상에서 사용할 수 있습니다.")
        }

        let availability = await Self.availability()
        guard availability.isSelectable else {
            throw STTError.engineUnavailable(availability.detailText ?? "SpeechAnalyzer를 사용할 수 없습니다.")
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
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            options: options,
            finishAfterFile: true
        )

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

        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        let text = try await resultTask.value
        return STTAudioUtilities.transcriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sampleCount: samples.count
        )
    }

    static func availability() async -> SpeechEngineAvailability {
        guard #available(macOS 26.0, *) else {
            return .unavailable("macOS 26 이상에서 사용할 수 있습니다.")
        }

        guard SpeechTranscriber.isAvailable else {
            return .unavailable("현재 기기에서 SpeechAnalyzer를 사용할 수 없습니다.")
        }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: STTAudioUtilities.koreanLocale) else {
            return .unavailable("한국어 SpeechAnalyzer 지원을 찾을 수 없습니다.")
        }

        let installedLocales = await SpeechTranscriber.installedLocales
        guard installedLocales.contains(where: { $0.identifier == locale.identifier }) else {
            return .unavailable("한국어 SpeechAnalyzer asset이 설치되어 있지 않습니다.")
        }

        return .available
    }
}
