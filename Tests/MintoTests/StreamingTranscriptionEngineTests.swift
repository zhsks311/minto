import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("StreamingTranscriptionEngine contract")
struct StreamingTranscriptionEngineTests {

    @Test("현재 등록된 엔진은 rolling preview와 true streaming을 구분한다")
    func currentEnginesDoNotClaimTrueStreaming() {
        for engine in SpeechEngineID.allCases {
            #expect(engine.supportsTrueStreaming == false)
        }

        #expect(SpeechEngineID.whisperAccurate.supportsPreviewTranscription == true)
        #expect(SpeechEngineID.whisperAccurate.supportsTrueStreaming == false)
    }

    @Test("streaming session은 partial과 final 이벤트를 분리해 전달한다")
    func streamingSessionSeparatesPartialAndFinalEvents() async throws {
        let engine = StubStreamingEngine()
        let session = try await engine.startSession(configuration: .init())
        var events: [StreamingTranscriptionEvent] = []
        session.onEvent = { event in
            events.append(event)
        }

        try await session.accept(pcmSamples: [Float](repeating: 0.4, count: 8_000))
        try await session.finish()

        #expect(events.map(\.kind) == [.partial, .final])
        #expect(events.map(\.segment.text) == ["부분 인식", "최종 인식"])
        #expect(events.map(\.revision) == [1, 2])
        #expect(engine.lastConfiguration == StreamingTranscriptionConfiguration())
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
