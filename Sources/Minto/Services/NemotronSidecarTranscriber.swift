import Foundation

@MainActor
final class NemotronSidecarTranscriber {
    private let client: any NemotronSidecarTranscribing
    private let makeRequestID: @Sendable () -> String

    init(
        client: any NemotronSidecarTranscribing = NemotronSidecarClient(),
        makeRequestID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.client = client
        self.makeRequestID = makeRequestID
    }

    func load(updateState: @escaping STTStateUpdater) async throws {
        updateState(.loading)
        let health = try await client.health()
        guard health.isReady else {
            let detail = health.detail ?? "status=\(health.status)"
            updateState(.failed(detail))
            throw STTError.engineUnavailable("Nemotron sidecar가 준비되지 않았어요: \(detail)")
        }
        updateState(.loaded)
    }

    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        let samples = STTAudioUtilities.paddedSamples(pcmSamples)
        if let silent = STTAudioUtilities.silentResultIfNeeded(samples) {
            return silent
        }

        let transcription = try await client.transcribe(
            pcmSamples: samples,
            requestID: makeRequestID()
        )
        return STTAudioUtilities.transcriptionResult(
            text: transcription.text,
            sampleCount: samples.count
        )
    }
}
