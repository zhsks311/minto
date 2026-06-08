import Foundation

struct StreamingTranscriptionConfiguration: Sendable, Equatable {
    let sampleRate: Double
    let locale: Locale

    init(
        sampleRate: Double = STTAudioUtilities.sampleRate,
        locale: Locale = STTAudioUtilities.koreanLocale
    ) {
        self.sampleRate = sampleRate
        self.locale = locale
    }
}

struct StreamingTranscriptionEvent: Sendable, Equatable {
    enum Kind: String, Sendable {
        case partial
        case final
    }

    let kind: Kind
    let segment: Segment
    let revision: Int

    static func partial(text: String, revision: Int, duration: TimeInterval) -> StreamingTranscriptionEvent {
        StreamingTranscriptionEvent(
            kind: .partial,
            segment: Segment(text: text, timestamp: Date(), duration: duration),
            revision: revision
        )
    }

    static func final(text: String, revision: Int, duration: TimeInterval) -> StreamingTranscriptionEvent {
        StreamingTranscriptionEvent(
            kind: .final,
            segment: Segment(text: text, timestamp: Date(), duration: duration),
            revision: revision
        )
    }
}

@MainActor
protocol StreamingTranscriptionSession: AnyObject {
    var onEvent: (@MainActor @Sendable (StreamingTranscriptionEvent) -> Void)? { get set }

    func accept(pcmSamples: [Float]) async throws
    func finish() async throws
    func reset() async
}

@MainActor
protocol StreamingTranscriptionEngine: AnyObject {
    var engineID: SpeechEngineID { get }

    func startSession(
        configuration: StreamingTranscriptionConfiguration
    ) async throws -> any StreamingTranscriptionSession
}

extension SpeechEngineID {
    var supportsTrueStreaming: Bool {
        switch self {
        case .whisperAccurate, .whisperBalanced, .whisperFast, .speechAnalyzer, .sfSpeechOnDevice:
            return false
        }
    }
}
