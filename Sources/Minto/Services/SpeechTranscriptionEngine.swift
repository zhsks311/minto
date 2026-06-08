import Foundation

typealias STTStateUpdater = @MainActor @Sendable (ModelState) -> Void

@MainActor
protocol SpeechTranscriptionEngine: AnyObject {
    var engineID: SpeechEngineID { get }
    var modelVariant: String { get }
    var supportsPreviewTranscription: Bool { get }

    func load(updateState: @escaping STTStateUpdater) async throws
    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult
}
