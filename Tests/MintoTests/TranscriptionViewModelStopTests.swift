import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("TranscriptionViewModel Stop/Drain")
struct TranscriptionViewModelStopTests {

    @Test("startNewRecordingSession은 이전 회의 전사와 미리보기를 새 세션에 남기지 않는다")
    func startNewRecordingSessionClearsPreviousSessionState() async throws {
        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "새 발화")
        let viewModel = TranscriptionViewModel(sttService: stt, audioSource: audioSource, vadProcessor: vad)

        viewModel.committedSegments = [
            Segment(text: "이전 테스트 회의 발화", timestamp: Date(), duration: 1.0)
        ]
        viewModel.pendingSegment = Segment(text: "이전 미리보기", timestamp: Date(), duration: 0.5)

        viewModel.startNewRecordingSession()

        #expect(viewModel.committedSegments.isEmpty)
        #expect(viewModel.pendingSegment == nil)
        #expect(audioSource.startCount == 1)
        #expect(vad.resetCount == 1)

        await viewModel.stopRecordingAndDrain()
        viewModel.clearTranscript()
    }

    @Test("startNewRecordingSession은 녹음 중이면 현재 세션을 지우지 않는다")
    func startNewRecordingSessionDoesNotClearActiveRecording() async throws {
        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "새 발화")
        let viewModel = TranscriptionViewModel(sttService: stt, audioSource: audioSource, vadProcessor: vad)
        let committed = Segment(text: "진행 중인 회의 발화", timestamp: Date(), duration: 1.0)
        let pending = Segment(text: "진행 중인 미리보기", timestamp: Date(), duration: 0.5)

        viewModel.startRecording()
        viewModel.committedSegments = [committed]
        viewModel.pendingSegment = pending

        viewModel.startNewRecordingSession()

        #expect(viewModel.committedSegments == [committed])
        #expect(viewModel.pendingSegment == pending)
        #expect(audioSource.startCount == 1)

        await viewModel.stopRecordingAndDrain()
        viewModel.clearTranscript()
    }

    @Test("stopRecordingAndDrain은 VAD 잔여 청크를 final 전사까지 drain한다")
    func stopRecordingDrainsPendingVADChunk() async throws {
        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "마지막 발화")
        let viewModel = TranscriptionViewModel(sttService: stt, audioSource: audioSource, vadProcessor: vad)

        let testStartedAt = Date()
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
        let segment = try #require(viewModel.committedSegments.first)
        #expect(segment.duration == 0.5)
        let offset = segment.timestamp.timeIntervalSince(testStartedAt)
        #expect(offset >= 0.9 && offset <= 1.5)

        viewModel.clearTranscript()
    }

    @Test("preview chunk도 오디오 offset 기반 timestamp와 duration을 사용한다")
    func previewChunkUsesAudioOffset() async throws {
        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "미리보기 발화")
        let viewModel = TranscriptionViewModel(sttService: stt, audioSource: audioSource, vadProcessor: vad)

        let testStartedAt = Date()
        viewModel.startRecording()
        vad.onPreviewChunk?(
            AudioChunk(
                samples: [Float](repeating: 0.5, count: 8_000),
                durationSeconds: 0.5,
                trailingSilence: 0,
                isPreview: true,
                startSeconds: 3.0,
                endSeconds: 3.75
            )
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        let pending = try #require(viewModel.pendingSegment)
        #expect(pending.text == "미리보기 발화")
        #expect(pending.duration == 0.75)
        let offset = pending.timestamp.timeIntervalSince(testStartedAt)
        #expect(offset >= 2.9 && offset <= 3.5)

        await viewModel.stopRecordingAndDrain()
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

    @Test("empty final repair가 켜져 있으면 원본 buffer에서 padding을 붙여 한 번 재전사한다")
    func emptyFinalRepairRetriesWithBufferedPadding() async throws {
        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultTexts: ["", "복구된 발화"])
        let policy = EmptyFinalRepairPolicy(
            isEnabled: true,
            padSeconds: 0.25,
            minChunkSeconds: 0.5,
            minAudioDB: -35,
            maxBufferedSeconds: 5
        )
        let viewModel = TranscriptionViewModel(
            sttService: stt,
            audioSource: audioSource,
            vadProcessor: vad,
            emptyFinalRepairPolicy: policy
        )

        viewModel.startRecording()
        audioSource.emit(samples: [Float](repeating: 0.5, count: 32_000))
        vad.pendingChunk = AudioChunk(
            samples: [Float](repeating: 0.5, count: 8_000),
            durationSeconds: 0.5,
            trailingSilence: 0,
            startSeconds: 0.5,
            endSeconds: 1.0
        )

        await viewModel.stopRecordingAndDrain()

        #expect(stt.transcribedSampleCounts == [8_000, 16_000])
        #expect(viewModel.committedSegments.map(\.text) == ["복구된 발화"])
        let segment = try #require(viewModel.committedSegments.first)
        #expect(segment.duration == 0.5)

        viewModel.clearTranscript()
    }

    @Test("empty final repair guard에 걸리면 재전사하지 않고 preview를 유지한다")
    func emptyFinalRepairGuardSkipsRetry() async throws {
        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultTexts: ["", "재시도되면 안 됨"])
        let policy = EmptyFinalRepairPolicy(
            isEnabled: true,
            padSeconds: 0.25,
            minChunkSeconds: 2.0,
            minAudioDB: -35,
            maxBufferedSeconds: 5
        )
        let viewModel = TranscriptionViewModel(
            sttService: stt,
            audioSource: audioSource,
            vadProcessor: vad,
            emptyFinalRepairPolicy: policy
        )
        let preview = Segment(text: "미리보기 발화", timestamp: Date(), duration: 0.8)

        viewModel.pendingSegment = preview
        viewModel.startRecording()
        audioSource.emit(samples: [Float](repeating: 0.5, count: 32_000))
        vad.pendingChunk = AudioChunk(
            samples: [Float](repeating: 0.5, count: 8_000),
            durationSeconds: 0.5,
            trailingSilence: 0,
            startSeconds: 0.5,
            endSeconds: 1.0
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
    private let resultTexts: [String]
    private(set) var transcribedSampleCounts: [Int] = []

    init(resultText: String) {
        self.resultTexts = [resultText]
    }

    init(resultTexts: [String]) {
        self.resultTexts = resultTexts.isEmpty ? [""] : resultTexts
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
        let text = resultTexts[min(transcribedSampleCounts.count, resultTexts.count - 1)]
        transcribedSampleCounts.append(pcmSamples.count)
        return TranscriptionResult(
            segment: Segment(text: text, timestamp: Date(), duration: Double(pcmSamples.count) / 16_000.0),
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

    func emit(samples: [Float]) {
        onBuffer?(samples)
    }
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
