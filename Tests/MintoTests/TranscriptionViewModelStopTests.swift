import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("TranscriptionViewModel Stop/Drain")
struct TranscriptionViewModelStopTests {

    @Test("stopRecordingAndDrain은 VAD 잔여 청크를 final 전사까지 drain한다")
    func stopRecordingDrainsPendingVADChunk() async throws {
        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "마지막 발화")
        let viewModel = TranscriptionViewModel(sttService: stt, audioSource: audioSource, vadProcessor: vad)

        viewModel.startRecording()
        vad.pendingChunk = AudioChunk(
            samples: [Float](repeating: 0.5, count: 8_000),
            durationSeconds: 0.5,
            trailingSilence: 0,
            startSeconds: 1.0,
            endSeconds: 1.5
        )

        await viewModel.stopRecordingAndDrain()

        #expect(audioSource.startCount == 1)
        #expect(audioSource.stopCount == 1)
        #expect(vad.resetCount == 1)
        #expect(vad.flushCount == 1)
        #expect(stt.transcribedSampleCounts == [8_000])
        #expect(viewModel.committedSegments.map(\.text) == ["마지막 발화"])

        viewModel.clearTranscript()
    }

    @Test("final STT가 비어 있으면 기존 preview를 즉시 지우지 않는다")
    func emptyFinalKeepsExistingPreview() async throws {
        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "")
        let viewModel = TranscriptionViewModel(sttService: stt, audioSource: audioSource, vadProcessor: vad)
        let preview = Segment(text: "미리보기 발화", timestamp: Date(), duration: 0.8)

        viewModel.pendingSegment = preview
        viewModel.startRecording()
        vad.pendingChunk = AudioChunk(
            samples: [Float](repeating: 0.5, count: 8_000),
            durationSeconds: 0.5,
            trailingSilence: 0,
            startSeconds: 2.0,
            endSeconds: 2.5
        )

        await viewModel.stopRecordingAndDrain()

        #expect(stt.transcribedSampleCounts == [8_000])
        #expect(viewModel.committedSegments.isEmpty)
        #expect(viewModel.pendingSegment == preview)

        viewModel.clearTranscript()
    }
}

@MainActor
private final class StubSTTService: TranscriptionSTTServicing {
    var modelState: ModelState = .loaded
    var modelVariant: String = "stub"
    var speechEngineID: SpeechEngineID = .whisperAccurate
    var supportsPreviewTranscription: Bool = true
    var onModelStateChange: ((ModelState) -> Void)?
    private let resultText: String
    private(set) var transcribedSampleCounts: [Int] = []

    init(resultText: String) {
        self.resultText = resultText
    }

    func loadEngine(_ engineID: SpeechEngineID) async {
        speechEngineID = engineID
    }

    func loadModel(variant: String) async {
        modelVariant = variant
    }

    func recoverModelCacheAndReload(variant: String) async {
        modelVariant = variant
    }

    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        transcribedSampleCounts.append(pcmSamples.count)
        return TranscriptionResult(
            segment: Segment(text: resultText, timestamp: Date(), duration: Double(pcmSamples.count) / 16_000.0),
            isFinal: true
        )
    }
}

private final class StubAudioSource: AudioSourceProtocol {
    var onBuffer: (@Sendable ([Float]) -> Void)?
    var onError: (@Sendable (AudioSourceError) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var availableDevices: [AudioDevice] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() throws {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func selectDevice(_ device: AudioDevice) throws {}
}

private final class StubVoiceActivityDetector: VoiceActivityDetector, @unchecked Sendable {
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onPreviewChunk: (@Sendable (AudioChunk) -> Void)?
    var pendingChunk: AudioChunk?
    private(set) var resetCount = 0
    private(set) var flushCount = 0
    private(set) var processedSampleCounts: [Int] = []

    func process(samples: [Float]) {
        processedSampleCounts.append(samples.count)
    }

    func flushPending() async -> AudioChunk? {
        flushCount += 1
        defer { pendingChunk = nil }
        return pendingChunk
    }

    func reset() {
        resetCount += 1
    }
}
