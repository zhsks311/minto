import Foundation

public struct Segment: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let duration: TimeInterval

    public init(id: UUID = UUID(), text: String, timestamp: Date, duration: TimeInterval) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
    }
}

public struct Meeting: Identifiable, Sendable {
    public let id: UUID
    public var startedAt: Date
    public var segments: [Segment]

    public init(id: UUID = UUID(), startedAt: Date = Date(), segments: [Segment] = []) {
        self.id = id
        self.startedAt = startedAt
        self.segments = segments
    }
}

public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let durationSeconds: Double
    public let trailingSilence: TimeInterval
    /// true이면 VAD가 아직 말 중인 동안 발행한 미리보기 청크 (pendingSegment 전용)
    public let isPreview: Bool

    public init(samples: [Float], durationSeconds: Double, trailingSilence: TimeInterval, isPreview: Bool = false) {
        self.samples = samples
        self.durationSeconds = durationSeconds
        self.trailingSilence = trailingSilence
        self.isPreview = isPreview
    }
}

public struct TranscriptionResult: Sendable {
    public let segment: Segment
    public let isFinal: Bool

    public init(segment: Segment, isFinal: Bool) {
        self.segment = segment
        self.isFinal = isFinal
    }
}

public struct AudioDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum AudioSourceError: Error, Sendable {
    case permissionDenied
    case configChangeFailed(Error)
    case deviceNotFound(AudioDevice)
    case engineStartFailed(Error)
}

public enum STTError: Error, LocalizedError, Sendable {
    case modelNotLoaded
    case transcriptionFailed(String)
    case engineUnavailable(String)
    case speechAuthorizationRequired(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "음성 인식 엔진이 아직 준비되지 않았습니다."
        case .transcriptionFailed(let message):
            return message
        case .engineUnavailable(let reason):
            return reason
        case .speechAuthorizationRequired(let reason):
            return reason
        }
    }
}

/// WhisperKit 모델 로딩 단계 상태
public enum ModelState: Sendable, Equatable {
    case unloaded
    case downloading(Double)
    case loading
    case loaded
    case failed(String)

    public static func == (lhs: ModelState, rhs: ModelState) -> Bool {
        switch (lhs, rhs) {
        case (.unloaded, .unloaded), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.downloading(let a), .downloading(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

public extension Notification.Name {
    static let transcriptionNeedsFlush = Notification.Name("MintoTranscriptionNeedsFlush")
}
