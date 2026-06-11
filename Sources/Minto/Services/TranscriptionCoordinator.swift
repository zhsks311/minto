import Foundation

enum TranscriptionCoordinatorError: Error, Equatable, LocalizedError {
    case streamingRouteRequired
    case streamingSessionAlreadyStarted
    case streamingSessionNotStarted

    var errorDescription: String? {
        switch self {
        case .streamingRouteRequired:
            return "true streaming route가 아닌 plan에서는 streaming session을 시작할 수 없어요."
        case .streamingSessionAlreadyStarted:
            return "streaming session이 이미 시작되어 있어요."
        case .streamingSessionNotStarted:
            return "시작된 streaming session이 없어요."
        }
    }
}

enum TranscriptionCoordinatorRoute: Equatable, Sendable {
    case oneShotVADChunks(rollingPreview: Bool)
    case trueStreamingSession
}

struct TranscriptionCoordinatorMetrics: Equatable, Sendable {
    var acceptedSampleCount: Int = 0
    var partialEventCount: Int = 0
    var finalEventCount: Int = 0
    var latestRevision: Int = 0
    var firstPartialLatency: TimeInterval?
    var finalLatency: TimeInterval?
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

@MainActor
final class TranscriptionCoordinator {
    let plan: TranscriptionCoordinatorPlan
    private(set) var metrics = TranscriptionCoordinatorMetrics()

    private let now: @MainActor @Sendable () -> Date
    private let onStreamingEvent: @MainActor @Sendable (StreamingTranscriptionEvent) -> Void
    private var streamingSession: (any StreamingTranscriptionSession)?
    private var streamingStartedAt: Date?

    init(
        plan: TranscriptionCoordinatorPlan,
        now: @escaping @MainActor @Sendable () -> Date = Date.init,
        onStreamingEvent: @escaping @MainActor @Sendable (StreamingTranscriptionEvent) -> Void
    ) {
        self.plan = plan
        self.now = now
        self.onStreamingEvent = onStreamingEvent
    }

    func startStreaming(
        engine: any StreamingTranscriptionEngine,
        configuration: StreamingTranscriptionConfiguration = StreamingTranscriptionConfiguration()
    ) async throws {
        guard case .trueStreamingSession = plan.route else {
            throw TranscriptionCoordinatorError.streamingRouteRequired
        }
        guard streamingSession == nil else {
            throw TranscriptionCoordinatorError.streamingSessionAlreadyStarted
        }

        metrics = TranscriptionCoordinatorMetrics()
        streamingStartedAt = now()
        let session = try await engine.startSession(configuration: configuration)
        session.onEvent = { [weak self] event in
            self?.recordStreamingEvent(event)
            self?.onStreamingEvent(event)
        }
        streamingSession = session
    }

    func acceptStreamingSamples(_ samples: [Float]) async throws {
        guard let streamingSession else {
            throw TranscriptionCoordinatorError.streamingSessionNotStarted
        }
        metrics.acceptedSampleCount += samples.count
        try await streamingSession.accept(pcmSamples: samples)
    }

    func finishStreaming() async throws {
        guard let streamingSession else {
            throw TranscriptionCoordinatorError.streamingSessionNotStarted
        }
        try await streamingSession.finish()
        self.streamingSession = nil
        streamingStartedAt = nil
    }

    func resetStreaming() async {
        await streamingSession?.reset()
        streamingSession = nil
        streamingStartedAt = nil
        metrics = TranscriptionCoordinatorMetrics()
    }

    private func recordStreamingEvent(_ event: StreamingTranscriptionEvent) {
        metrics.latestRevision = max(metrics.latestRevision, event.revision)
        switch event.kind {
        case .partial:
            metrics.partialEventCount += 1
            if metrics.firstPartialLatency == nil, let streamingStartedAt {
                metrics.firstPartialLatency = now().timeIntervalSince(streamingStartedAt)
            }
        case .final:
            metrics.finalEventCount += 1
            if let streamingStartedAt {
                metrics.finalLatency = now().timeIntervalSince(streamingStartedAt)
            }
        }
    }
}
