import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("TranscriptionViewModel Stop/Drain", .serialized)
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

    @Test("mixed mode는 dominant channel로 final segment speaker를 채운다")
    func mixedModeLabelsFinalSegmentFromDominantChannel() async throws {
        let audioSource = StubAudioSource()
        audioSource.dominantChannelResult = .microphone
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "내 발화")
        let viewModel = TranscriptionViewModel(sttService: stt, audioSource: audioSource, vadProcessor: vad)

        viewModel.startNewRecordingSession(inputMode: .mixed)
        vad.pendingChunk = AudioChunk(
            samples: [Float](repeating: 0.5, count: 8_000),
            durationSeconds: 0.5,
            trailingSilence: 0,
            startSeconds: 1.0,
            endSeconds: 1.5
        )

        await viewModel.stopRecordingAndDrain()

        let segment = try #require(viewModel.committedSegments.first)
        #expect(segment.speaker == kSpeakerSelfLabel)
        #expect(audioSource.resetChannelActivityCount == 1)
        #expect(audioSource.dominantChannelRequests.count == 1)
        #expect(audioSource.dominantChannelRequests.first?.startSeconds == 1.0)
        #expect(audioSource.dominantChannelRequests.first?.endSeconds == 1.5)

        viewModel.clearTranscript()
    }

    @Test("microphone mode는 provider가 있어도 speaker를 채우지 않는다")
    func microphoneModeKeepsSpeakerNil() async throws {
        let audioSource = StubAudioSource()
        audioSource.dominantChannelResult = .microphone
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "마이크 발화")
        let viewModel = TranscriptionViewModel(sttService: stt, audioSource: audioSource, vadProcessor: vad)

        viewModel.startRecording()
        vad.pendingChunk = AudioChunk(
            samples: [Float](repeating: 0.5, count: 8_000),
            durationSeconds: 0.5,
            trailingSilence: 0,
            startSeconds: 0.0,
            endSeconds: 0.5
        )

        await viewModel.stopRecordingAndDrain()

        let segment = try #require(viewModel.committedSegments.first)
        #expect(segment.speaker == nil)
        #expect(audioSource.dominantChannelRequests.isEmpty)

        viewModel.clearTranscript()
    }

    @Test("mixed mode에서 preview segment는 speaker를 채우지 않는다 (final만 라벨)")
    func mixedModePreviewSegmentKeepsSpeakerNil() async throws {
        let audioSource = StubAudioSource()
        audioSource.dominantChannelResult = .microphone
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "미리보기 발화")
        let viewModel = TranscriptionViewModel(sttService: stt, audioSource: audioSource, vadProcessor: vad)

        viewModel.startNewRecordingSession(inputMode: .mixed)
        vad.onPreviewChunk?(
            AudioChunk(
                samples: [Float](repeating: 0.5, count: 8_000),
                durationSeconds: 0.5,
                trailingSilence: 0,
                isPreview: true,
                startSeconds: 1.0,
                endSeconds: 1.5
            )
        )
        await waitUntil { viewModel.pendingSegment != nil }

        let pending = try #require(viewModel.pendingSegment)
        // preview는 발화가 끝나지 않아 채널 판정이 불완전 → 라벨을 붙이지 않는다(깜빡임 방지).
        #expect(pending.speaker == nil)
        #expect(audioSource.dominantChannelRequests.isEmpty)

        await viewModel.stopRecordingAndDrain()
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
        // 고정 sleep은 병렬 부하에서 preview 전사 완료 전에 깨어나 flaky했다 — 조건 대기로 교체.
        await waitUntil { viewModel.pendingSegment != nil }

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

    @Test("교정이 꺼져 있어도 원문 batch로 진행 중 요약을 갱신한다")
    func summaryUsesOriginalBatchWhenCorrectionOff() async throws {
        let savedProvider = LLMCorrectionService.shared.selectedProvider
        defer { LLMCorrectionService.shared.selectedProvider = savedProvider }
        LLMCorrectionService.shared.selectedProvider = .none

        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "원문 발화")
        let summary = StubSummaryGenerator()
        let viewModel = TranscriptionViewModel(
            sttService: stt,
            audioSource: audioSource,
            vadProcessor: vad,
            summaryService: summary
        )

        viewModel.startRecording()
        vad.pendingChunk = AudioChunk(
            samples: [Float](repeating: 0.5, count: 8_000),
            durationSeconds: 0.5,
            trailingSilence: 0,
            startSeconds: 0.0,
            endSeconds: 0.5
        )

        await viewModel.stopRecordingAndDrain()
        _ = await viewModel.finalizeMeeting()
        await waitUntil { summary.incrementalBatches.count == 1 }

        #expect(viewModel.committedSegments.map(\.text) == ["원문 발화"])
        #expect(summary.incrementalBatches == ["원문 발화"])

        viewModel.clearTranscript()
    }

    @Test("녹음 중 provider 변경은 진행 중인 증분 요약을 취소하고 같은 배치를 다시 시도한다")
    func providerChangeDuringRecordingRetriesInFlightSummaryBatch() async throws {
        let savedProvider = LLMCorrectionService.shared.selectedProvider
        defer { LLMCorrectionService.shared.selectedProvider = savedProvider }
        LLMCorrectionService.shared.selectedProvider = .none

        let audioSource = StubAudioSource()
        let vad = StubVoiceActivityDetector()
        let stt = StubSTTService(resultText: "전환 전 배치")
        let summary = BlockingSummaryGenerator()
        let viewModel = TranscriptionViewModel(
            sttService: stt,
            audioSource: audioSource,
            vadProcessor: vad,
            summaryService: summary
        )

        viewModel.startRecording()
        vad.onChunk?(
            AudioChunk(
                samples: [Float](repeating: 0.5, count: 8_000),
                durationSeconds: 31,
                trailingSilence: 0,
                startSeconds: 0,
                endSeconds: 31
            )
        )
        await waitUntil { summary.incrementalBatches.count == 1 }

        LLMCorrectionService.shared.selectedProvider = .codex
        await waitUntil { summary.incrementalBatches.count >= 2 }

        #expect(Array(summary.incrementalBatches.prefix(2)) == ["전환 전 배치", "전환 전 배치"])
        #expect(summary.cancelledCallCount >= 1)

        await viewModel.stopRecordingAndDrain()
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

private final class StubAudioSource: AudioSourceProtocol, RecordingChannelActivityProviding {
    var onBuffer: (@Sendable ([Float]) -> Void)?
    var onError: (@Sendable (AudioSourceError) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var availableDevices: [AudioDevice] = []
    var dominantChannelResult: MixedAudioInputSource?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var resetChannelActivityCount = 0
    private(set) var dominantChannelRequests: [(startSeconds: Double, endSeconds: Double)] = []

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

    func dominantChannel(startSeconds: Double, endSeconds: Double) -> MixedAudioInputSource? {
        dominantChannelRequests.append((startSeconds, endSeconds))
        return dominantChannelResult
    }

    func resetChannelActivity() {
        resetChannelActivityCount += 1
        dominantChannelRequests.removeAll()
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

@MainActor
private final class StubSummaryGenerator: TranscriptionSummaryGenerating {
    private(set) var incrementalBatches: [String] = []
    private(set) var finalTranscripts: [String] = []

    func generateIncremental(correctedBatch: String) async -> String? {
        incrementalBatches.append(correctedBatch)
        return correctedBatch
    }

    func generateFinal(transcript: String) async -> MeetingSummary? {
        finalTranscripts.append(transcript)
        return nil
    }
}

@MainActor
private final class BlockingSummaryGenerator: TranscriptionSummaryGenerating {
    private(set) var incrementalBatches: [String] = []
    private(set) var cancelledCallCount = 0

    func generateIncremental(correctedBatch: String) async -> String? {
        incrementalBatches.append(correctedBatch)
        if incrementalBatches.count == 1 {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            cancelledCallCount += 1
            return nil
        }
        return correctedBatch
    }

    func generateFinal(transcript: String) async -> MeetingSummary? {
        nil
    }
}

@MainActor
// 타임아웃은 실패 한계일 뿐 정상 경로는 조건 충족 즉시 반환한다.
// 500ms는 병렬 전체 테스트 부하에서 간헐 초과(flaky)가 관측돼 5초로 늘렸다.
private func waitUntil(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let started = DispatchTime.now().uptimeNanoseconds
    while !condition(), DispatchTime.now().uptimeNanoseconds - started < timeoutNanoseconds {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
