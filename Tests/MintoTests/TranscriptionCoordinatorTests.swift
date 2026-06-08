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
}
