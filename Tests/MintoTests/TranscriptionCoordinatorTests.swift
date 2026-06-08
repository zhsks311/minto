import Foundation
import Testing
@testable import MintoCore

@Suite("TranscriptionCoordinator route planning")
struct TranscriptionCoordinatorTests {

    @Test("WhisperKit 계열은 VAD chunk one-shot과 rolling preview를 사용한다")
    func whisperUsesOneShotWithRollingPreview() {
        let plan = TranscriptionCoordinatorPlan.make(engineID: .whisperAccurate)

        #expect(plan.route == .oneShotVADChunks(rollingPreview: true))
        #expect(plan.usesVoiceActivityDetector)
        #expect(!plan.acceptsContinuousAudio)
    }

    @Test("현재 Apple final-only 엔진은 VAD chunk one-shot으로 남긴다")
    func appleFinalOnlyEnginesUseOneShotWithoutPreview() {
        for engine in [SpeechEngineID.speechAnalyzer, .sfSpeechOnDevice] {
            let plan = TranscriptionCoordinatorPlan.make(engineID: engine)

            #expect(plan.route == .oneShotVADChunks(rollingPreview: false))
            #expect(plan.usesVoiceActivityDetector)
            #expect(!plan.acceptsContinuousAudio)
        }
    }

    @Test("true streaming capability가 있으면 VAD one-shot 경로를 타지 않는다")
    func trueStreamingCapabilityUsesStreamingSession() {
        let plan = TranscriptionCoordinatorPlan.make(
            capabilities: TranscriptionCoordinatorCapabilities(
                supportsPreviewTranscription: true,
                supportsTrueStreaming: true
            )
        )

        #expect(plan.route == .trueStreamingSession)
        #expect(!plan.usesVoiceActivityDetector)
        #expect(plan.acceptsContinuousAudio)
    }

    @MainActor
    @Test("one-shot plan은 streaming session 시작을 거부한다")
    func oneShotPlanRejectsStreamingStart() async throws {
        let plan = TranscriptionCoordinatorPlan.make(engineID: .whisperAccurate)
        let coordinator = TranscriptionCoordinator(plan: plan) { _ in }

        do {
            try await coordinator.startStreaming(engine: StubStreamingEngine())
            Issue.record("one-shot plan에서 streaming session이 시작되면 안 된다")
        } catch let error as TranscriptionCoordinatorError {
            #expect(error == .streamingRouteRequired)
        }
    }

    @MainActor
    @Test("true streaming plan은 session event와 metric을 기록한다")
    func trueStreamingPlanDrivesSessionEvents() async throws {
        let clock = StubClock()
        var events: [StreamingTranscriptionEvent] = []
        let plan = TranscriptionCoordinatorPlan.make(
            capabilities: TranscriptionCoordinatorCapabilities(
                supportsPreviewTranscription: false,
                supportsTrueStreaming: true
            )
        )
        let coordinator = TranscriptionCoordinator(
            plan: plan,
            now: { clock.now() },
            onStreamingEvent: { event in
                events.append(event)
            }
        )
        let engine = StubStreamingEngine()

        try await coordinator.startStreaming(engine: engine)
        clock.elapsed = 0.25
        try await coordinator.acceptStreamingSamples([Float](repeating: 0.4, count: 8_000))
        clock.elapsed = 1.25
        try await coordinator.finishStreaming()

        #expect(events.map(\.kind) == [.partial, .final])
        #expect(events.map(\.segment.text) == ["부분 인식", "최종 인식"])
        #expect(coordinator.metrics.acceptedSampleCount == 8_000)
        #expect(coordinator.metrics.partialEventCount == 1)
        #expect(coordinator.metrics.finalEventCount == 1)
        #expect(coordinator.metrics.latestRevision == 2)
        #expect(coordinator.metrics.firstPartialLatency == 0.25)
        #expect(coordinator.metrics.finalLatency == 1.25)
        #expect(engine.lastConfiguration == StreamingTranscriptionConfiguration())
    }
}

@MainActor
private final class StubClock: @unchecked Sendable {
    var elapsed: TimeInterval = 0

    func now() -> Date {
        Date(timeIntervalSince1970: 1_000 + elapsed)
    }
}

@MainActor
private final class StubStreamingEngine: StreamingTranscriptionEngine {
    let engineID: SpeechEngineID = .speechAnalyzer
    private(set) var lastConfiguration: StreamingTranscriptionConfiguration?

    func startSession(
        configuration: StreamingTranscriptionConfiguration
    ) async throws -> any StreamingTranscriptionSession {
        lastConfiguration = configuration
        return StubStreamingSession()
    }
}

@MainActor
private final class StubStreamingSession: StreamingTranscriptionSession {
    var onEvent: (@MainActor @Sendable (StreamingTranscriptionEvent) -> Void)?
    private var revision = 0

    func accept(pcmSamples: [Float]) async throws {
        revision += 1
        onEvent?(.partial(
            text: "부분 인식",
            revision: revision,
            duration: Double(pcmSamples.count) / STTAudioUtilities.sampleRate
        ))
    }

    func finish() async throws {
        revision += 1
        onEvent?(.final(text: "최종 인식", revision: revision, duration: 0))
    }

    func reset() async {
        revision = 0
    }
}
