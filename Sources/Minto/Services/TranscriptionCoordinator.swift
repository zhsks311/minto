import Foundation

enum TranscriptionCoordinatorRoute: Equatable, Sendable {
    case oneShotVADChunks(rollingPreview: Bool)
    case trueStreamingSession
}

struct TranscriptionCoordinatorCapabilities: Equatable, Sendable {
    let supportsPreviewTranscription: Bool
    let supportsTrueStreaming: Bool

    init(engineID: SpeechEngineID) {
        self.init(
            supportsPreviewTranscription: engineID.supportsPreviewTranscription,
            supportsTrueStreaming: engineID.supportsTrueStreaming
        )
    }

    init(supportsPreviewTranscription: Bool, supportsTrueStreaming: Bool) {
        self.supportsPreviewTranscription = supportsPreviewTranscription
        self.supportsTrueStreaming = supportsTrueStreaming
    }
}

struct TranscriptionCoordinatorPlan: Equatable, Sendable {
    let route: TranscriptionCoordinatorRoute
    let usesVoiceActivityDetector: Bool
    let acceptsContinuousAudio: Bool

    static func make(
        capabilities: TranscriptionCoordinatorCapabilities
    ) -> TranscriptionCoordinatorPlan {
        if capabilities.supportsTrueStreaming {
            return TranscriptionCoordinatorPlan(
                route: .trueStreamingSession,
                usesVoiceActivityDetector: false,
                acceptsContinuousAudio: true
            )
        }

        return TranscriptionCoordinatorPlan(
            route: .oneShotVADChunks(rollingPreview: capabilities.supportsPreviewTranscription),
            usesVoiceActivityDetector: true,
            acceptsContinuousAudio: false
        )
    }

    static func make(engineID: SpeechEngineID) -> TranscriptionCoordinatorPlan {
        make(capabilities: TranscriptionCoordinatorCapabilities(engineID: engineID))
    }
}
