import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("TranscriptionViewModel Live Speaker Assignment")
struct TranscriptionViewModelLiveSpeakerTests {
    @Test("라이브 화자 라벨은 시간 겹침으로 committed segment에 바인딩된다")
    func assignsLiveSpeakerLabelToCommittedSegment() async throws {
        let provider = LiveSpeakerMockStreamingProvider(
            processResponses: [
                [diarizedSegment("speaker-a", start: 0.0, end: 1.0)],
            ]
        )
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)
        let audioSource = LiveSpeakerStubAudioSource()
        let viewModel = makeViewModel(
            resultTexts: ["첫 발화"],
            audioSource: audioSource,
            liveSpeakerAssignment: useCase
        )

        viewModel.startRecording()
        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 1
        })

        viewModel.enqueueChunk(audioChunk(start: 0.0, end: 1.0))
        #expect(await waitUntil {
            viewModel.committedSegments.first?.speaker == "화자 1"
        })

        let segment = try #require(viewModel.committedSegments.first)
        #expect(segment.text == "첫 발화")
        #expect(segment.speaker == "화자 1")
        let snapshot = await provider.snapshot()
        #expect(snapshot.startPreEnrolledCounts == [0])

        await viewModel.stopRecordingAndDrain()
        viewModel.clearTranscript()
    }

    @Test("다화자 라이브 스냅샷은 committed segment를 서로 다른 라벨로 갱신한다")
    func assignsMultipleLiveSpeakerLabelsFromSnapshot() async throws {
        let provider = LiveSpeakerMockStreamingProvider(
            processResponses: [
                [diarizedSegment("speaker-a", start: 0.0, end: 2.0)],
                [
                    diarizedSegment("speaker-a", start: 0.0, end: 1.0),
                    diarizedSegment("speaker-b", start: 1.0, end: 2.0),
                ],
            ]
        )
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)
        let audioSource = LiveSpeakerStubAudioSource()
        let viewModel = makeViewModel(
            resultTexts: ["첫 발화", "둘째 발화"],
            audioSource: audioSource,
            liveSpeakerAssignment: useCase
        )

        viewModel.startRecording()
        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 1
        })

        viewModel.enqueueChunk(audioChunk(start: 0.0, end: 1.0))
        viewModel.enqueueChunk(audioChunk(start: 1.0, end: 2.0))
        #expect(await waitUntil {
            viewModel.committedSegments.count == 2
                && viewModel.committedSegments.allSatisfy { $0.speaker == "화자 1" }
        })

        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 2
                && viewModel.committedSegments.map(\.speaker) == ["화자 1", "화자 2"]
        })

        await viewModel.stopRecordingAndDrain()
        viewModel.clearTranscript()
    }

    @Test("수동 reassign한 segment는 이후 라이브 바인딩이 덮어쓰지 않는다")
    func reassignProtectsSegmentFromLaterLiveBinding() async throws {
        let provider = LiveSpeakerMockStreamingProvider(
            processResponses: [
                [diarizedSegment("speaker-a", start: 0.0, end: 0.6)],
                [diarizedSegment("speaker-b", start: 0.0, end: 1.0)],
            ]
        )
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)
        let audioSource = LiveSpeakerStubAudioSource()
        let viewModel = makeViewModel(
            resultTexts: ["첫 발화"],
            audioSource: audioSource,
            liveSpeakerAssignment: useCase
        )

        viewModel.startRecording()
        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 1
        })

        viewModel.enqueueChunk(audioChunk(start: 0.0, end: 1.0))
        #expect(await waitUntil {
            viewModel.committedSegments.first?.speaker == "화자 1"
        })

        let segment = try #require(viewModel.committedSegments.first)
        viewModel.reassignLiveSpeaker(segmentId: segment.id, to: "박팀장")

        #expect(viewModel.committedSegments.first?.speaker == "박팀장")
        #expect(viewModel.editedSpeakerSegmentIds.contains(segment.id))

        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 2
        })
        await waitForMainQueueTurn()

        #expect(viewModel.committedSegments.first?.speaker == "박팀장")

        await viewModel.stopRecordingAndDrain()
        viewModel.clearTranscript()
    }

    @Test("수동 rename한 라벨의 모든 segment는 이후 라이브 바인딩이 덮어쓰지 않는다")
    func renameProtectsAllMatchingSegmentsFromLaterLiveBinding() async throws {
        let provider = LiveSpeakerMockStreamingProvider(
            processResponses: [
                [
                    diarizedSegment("speaker-a", start: 0.0, end: 0.6),
                    diarizedSegment("speaker-a", start: 1.0, end: 1.6),
                ],
                [diarizedSegment("speaker-b", start: 0.0, end: 2.0)],
            ]
        )
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)
        let audioSource = LiveSpeakerStubAudioSource()
        let viewModel = makeViewModel(
            resultTexts: ["첫 발화", "둘째 발화"],
            audioSource: audioSource,
            liveSpeakerAssignment: useCase
        )

        viewModel.startRecording()
        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 1
        })

        viewModel.enqueueChunk(audioChunk(start: 0.0, end: 1.0))
        viewModel.enqueueChunk(audioChunk(start: 1.0, end: 2.0))
        #expect(await waitUntil {
            viewModel.committedSegments.count == 2
                && viewModel.committedSegments.allSatisfy { $0.speaker == "화자 1" }
        })

        let editedIds = Set(viewModel.committedSegments.map(\.id))
        viewModel.renameLiveSpeaker(from: "화자 1", to: "김재휘")

        #expect(viewModel.committedSegments.map { $0.speaker ?? "" } == ["김재휘", "김재휘"])
        #expect(editedIds.isSubset(of: viewModel.editedSpeakerSegmentIds))

        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 2
        })
        await waitForMainQueueTurn()

        #expect(viewModel.committedSegments.map { $0.speaker ?? "" } == ["김재휘", "김재휘"])

        await viewModel.stopRecordingAndDrain()
        viewModel.clearTranscript()
    }

    @Test("liveSpeakerAssignment 기본 nil 경로는 speaker를 채우지 않는다")
    func nilLiveSpeakerAssignmentPreservesExistingSpeakerBehavior() async throws {
        let viewModel = makeViewModel(resultTexts: ["기존 전사"])

        viewModel.startRecording()
        viewModel.enqueueChunk(audioChunk(start: 0.0, end: 1.0))
        #expect(await waitUntil {
            viewModel.committedSegments.count == 1
        })

        let segment = try #require(viewModel.committedSegments.first)
        #expect(segment.text == "기존 전사")
        #expect(segment.speaker == nil)

        await viewModel.stopRecordingAndDrain()
        viewModel.clearTranscript()
    }

    @Test("라이브 provider가 throw해도 전사 segment 텍스트는 유지된다")
    func providerFailureDoesNotBreakTranscription() async throws {
        let provider = LiveSpeakerMockStreamingProvider(failure: .process)
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)
        let audioSource = LiveSpeakerStubAudioSource()
        let viewModel = makeViewModel(
            resultTexts: ["살아남은 전사"],
            audioSource: audioSource,
            liveSpeakerAssignment: useCase
        )

        viewModel.startRecording()
        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 1
        })

        viewModel.enqueueChunk(audioChunk(start: 0.0, end: 1.0))
        #expect(await waitUntil {
            viewModel.committedSegments.count == 1
        })

        let segment = try #require(viewModel.committedSegments.first)
        #expect(segment.text == "살아남은 전사")
        #expect(segment.speaker == nil)
        #expect(viewModel.errorMessage == nil)

        await viewModel.stopRecordingAndDrain()
        viewModel.clearTranscript()
    }

    @Test("라이브 provider 실패 후 mixed 입력은 채널 라벨로 자동 강등된다")
    func providerFailureRestoresChannelLabelsForMixedInput() async throws {
        let provider = LiveSpeakerMockStreamingProvider(
            processResponses: [
                [diarizedSegment("speaker-a", start: 0.0, end: 2.0)],
            ],
            processFailureCall: 2
        )
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)
        let audioSource = LiveSpeakerChannelStubAudioSource(
            channels: [
                (start: 0.0, end: 1.0, channel: .microphone),
                (start: 1.0, end: 3.0, channel: .systemAudio),
            ]
        )
        let viewModel = makeViewModel(
            resultTexts: ["첫 발화", "둘째 발화", "셋째 발화"],
            audioSource: audioSource,
            liveSpeakerAssignment: useCase
        )

        viewModel.startNewRecordingSession(inputMode: .mixed)
        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 1
        })

        viewModel.enqueueChunk(audioChunk(start: 0.0, end: 1.0))
        viewModel.enqueueChunk(audioChunk(start: 1.0, end: 2.0))
        #expect(await waitUntil {
            viewModel.committedSegments.count == 2
                && viewModel.committedSegments.allSatisfy { $0.speaker == "화자 1" }
        })

        let editedSegment = try #require(viewModel.committedSegments.last)
        viewModel.reassignLiveSpeaker(segmentId: editedSegment.id, to: "고정 라벨")

        audioSource.emit(samples: samples(count: 16_000))
        #expect(await waitUntil {
            let snapshot = await provider.snapshot()
            return snapshot.processCallCount == 2
                && viewModel.committedSegments.first?.speaker == kSpeakerSelfLabel
        })

        #expect(viewModel.committedSegments.map(\.speaker) == [kSpeakerSelfLabel, "고정 라벨"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.allText == "첫 발화\n둘째 발화")

        viewModel.enqueueChunk(audioChunk(start: 2.0, end: 3.0))
        #expect(await waitUntil {
            viewModel.committedSegments.count == 3
                && viewModel.committedSegments.last?.speaker == kSpeakerOtherLabel
        })

        #expect(viewModel.committedSegments.map(\.speaker) == [
            kSpeakerSelfLabel,
            "고정 라벨",
            kSpeakerOtherLabel,
        ])
        #expect(viewModel.allText == "첫 발화\n둘째 발화\n셋째 발화")

        await viewModel.stopRecordingAndDrain()
        #expect(viewModel.committedSegments.map(\.speaker) == [
            kSpeakerSelfLabel,
            "고정 라벨",
            kSpeakerOtherLabel,
        ])
        viewModel.clearTranscript()
    }

    private func makeViewModel(
        resultTexts: [String],
        audioSource: any AudioSourceProtocol = LiveSpeakerStubAudioSource(),
        liveSpeakerAssignment: LiveSpeakerAssignmentUseCase? = nil
    ) -> TranscriptionViewModel {
        TranscriptionViewModel(
            sttService: LiveSpeakerStubSTTService(resultTexts: resultTexts),
            audioSource: audioSource,
            vadProcessor: LiveSpeakerStubVoiceActivityDetector(),
            emptyFinalRepairPolicy: .disabled,
            liveSpeakerAssignment: liveSpeakerAssignment
        )
    }
}

@MainActor
private final class LiveSpeakerStubSTTService: TranscriptionSTTServicing {
    var modelState: ModelState = .loaded
    var modelVariant: String = "stub"
    var speechEngineID: SpeechEngineID = .whisperAccurate
    var supportsPreviewTranscription: Bool = true
    var onModelStateChange: ((ModelState) -> Void)?

    private let resultTexts: [String]
    private var transcribeCount = 0

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
        let text = resultTexts[min(transcribeCount, resultTexts.count - 1)]
        transcribeCount += 1
        return TranscriptionResult(
            segment: Segment(
                text: text,
                timestamp: Date(),
                duration: Double(pcmSamples.count) / STTAudioUtilities.sampleRate
            ),
            isFinal: true
        )
    }
}

private final class LiveSpeakerStubAudioSource: AudioSourceProtocol {
    var onBuffer: (@Sendable ([Float]) -> Void)?
    var onError: (@Sendable (AudioSourceError) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var availableDevices: [AudioDevice] = []

    func start() throws {}

    func stop() {}

    func selectDevice(_ device: AudioDevice) throws {}

    func emit(samples: [Float]) {
        onBuffer?(samples)
    }
}

private final class LiveSpeakerChannelStubAudioSource: AudioSourceProtocol, RecordingChannelActivityProviding {
    var onBuffer: (@Sendable ([Float]) -> Void)?
    var onError: (@Sendable (AudioSourceError) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var availableDevices: [AudioDevice] = []

    private let channels: [(start: Double, end: Double, channel: MixedAudioInputSource)]

    init(channels: [(start: Double, end: Double, channel: MixedAudioInputSource)]) {
        self.channels = channels
    }

    func start() throws {}

    func stop() {}

    func selectDevice(_ device: AudioDevice) throws {}

    func emit(samples: [Float]) {
        onBuffer?(samples)
    }

    func dominantChannel(startSeconds: Double, endSeconds: Double) -> MixedAudioInputSource? {
        channels.first {
            startSeconds >= $0.start && endSeconds <= $0.end
        }?.channel
    }

    func resetChannelActivity() {}
}

private final class LiveSpeakerStubVoiceActivityDetector: VoiceActivityDetector, @unchecked Sendable {
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onPreviewChunk: (@Sendable (AudioChunk) -> Void)?

    func process(samples: [Float]) {}

    func flushPending() async -> AudioChunk? {
        nil
    }

    func reset() {}
}

private actor LiveSpeakerMockStreamingProvider: StreamingSpeakerDiarizationProvider {
    private var processResponses: [[DiarizedSpeakerSegment]]
    private let finishResponse: [DiarizedSpeakerSegment]
    private let failure: LiveSpeakerMockProviderFailure?
    private let processFailureCall: Int?
    private var startPreEnrolledCounts: [Int] = []
    private var processCallCount = 0
    private var finishCallCount = 0

    init(
        processResponses: [[DiarizedSpeakerSegment]] = [],
        finishResponse: [DiarizedSpeakerSegment] = [],
        failure: LiveSpeakerMockProviderFailure? = nil,
        processFailureCall: Int? = nil
    ) {
        self.processResponses = processResponses
        self.finishResponse = finishResponse
        self.failure = failure
        self.processFailureCall = processFailureCall
    }

    func start(preEnrolled: [Voiceprint]) async throws {
        startPreEnrolledCounts.append(preEnrolled.count)
        if failure == .start {
            throw LiveSpeakerMockProviderError.failed
        }
    }

    func process(
        samples: [Float],
        sourceSampleRate: Double
    ) async throws -> [DiarizedSpeakerSegment] {
        processCallCount += 1
        if failure == .process || processFailureCall == processCallCount {
            throw LiveSpeakerMockProviderError.failed
        }
        guard !processResponses.isEmpty else {
            return []
        }
        return processResponses.removeFirst()
    }

    func finish() async throws -> [DiarizedSpeakerSegment] {
        finishCallCount += 1
        if failure == .finish {
            throw LiveSpeakerMockProviderError.failed
        }
        return finishResponse
    }

    func snapshot() -> LiveSpeakerMockProviderSnapshot {
        LiveSpeakerMockProviderSnapshot(
            startPreEnrolledCounts: startPreEnrolledCounts,
            processCallCount: processCallCount,
            finishCallCount: finishCallCount
        )
    }
}

private struct LiveSpeakerMockProviderSnapshot: Equatable, Sendable {
    let startPreEnrolledCounts: [Int]
    let processCallCount: Int
    let finishCallCount: Int
}

private enum LiveSpeakerMockProviderFailure: Equatable, Sendable {
    case start
    case process
    case finish
}

private enum LiveSpeakerMockProviderError: Error, Equatable, Sendable {
    case failed
}

private func diarizedSegment(
    _ speakerId: String,
    start: Double,
    end: Double
) -> DiarizedSpeakerSegment {
    DiarizedSpeakerSegment(
        speakerId: speakerId,
        startSeconds: start,
        endSeconds: end
    )
}

private func audioChunk(start: Double, end: Double) -> AudioChunk {
    AudioChunk(
        samples: samples(count: Int((end - start) * STTAudioUtilities.sampleRate)),
        durationSeconds: end - start,
        trailingSilence: 0,
        startSeconds: start,
        endSeconds: end
    )
}

private func samples(count: Int) -> [Float] {
    [Float](repeating: 0.2, count: count)
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    condition: @escaping @MainActor () async -> Bool
) async -> Bool {
    let started = DispatchTime.now().uptimeNanoseconds
    while !(await condition()),
          DispatchTime.now().uptimeNanoseconds - started < timeoutNanoseconds {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

@MainActor
private func waitForMainQueueTurn() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}
