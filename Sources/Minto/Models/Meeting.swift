import Foundation

public struct WordTimestamp: Sendable, Hashable, Codable {
    public let word: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(word: String, start: TimeInterval, end: TimeInterval) {
        self.word = word
        self.start = start
        self.end = end
    }
}

public struct Segment: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let duration: TimeInterval
    public var speaker: String?
    public var words: [WordTimestamp]?

    public init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date,
        duration: TimeInterval,
        speaker: String? = nil,
        words: [WordTimestamp]? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.speaker = speaker
        self.words = words
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
    public let startSeconds: Double?
    public let endSeconds: Double?
    /// true이면 VAD가 아직 말 중인 동안 발행한 미리보기 청크 (pendingSegment 전용)
    public let isPreview: Bool

    public init(
        samples: [Float],
        durationSeconds: Double,
        trailingSilence: TimeInterval,
        isPreview: Bool = false,
        startSeconds: Double? = nil,
        endSeconds: Double? = nil
    ) {
        self.samples = samples
        self.durationSeconds = durationSeconds
        self.trailingSilence = trailingSilence
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
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

public enum AudioInputMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case microphone
    case systemAudio
    case mixed

    public var id: String { rawValue }

    public static let selectableCases: [AudioInputMode] = [.microphone, .systemAudio, .mixed]

    public var title: String {
        switch self {
        case .microphone:
            return "마이크"
        case .systemAudio:
            return "시스템"
        case .mixed:
            return "마이크+시스템"
        }
    }

    public var detail: String {
        switch self {
        case .microphone:
            return "내 목소리 중심"
        case .systemAudio:
            return "화상회의 상대방 소리"
        case .mixed:
            return "내 목소리와 상대방 소리"
        }
    }

    public var requiresScreenCapturePermission: Bool {
        self != .microphone
    }
}

public enum AudioInputReadinessState: String, Sendable, Equatable {
    case checking
    case ready
    case permissionRequired
    case unavailable
}

public struct AudioInputReadiness: Sendable, Equatable {
    public let state: AudioInputReadinessState
    public let title: String
    public let detail: String
    public let actionTitle: String?

    public init(
        state: AudioInputReadinessState,
        title: String,
        detail: String,
        actionTitle: String? = nil
    ) {
        self.state = state
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
    }

    public var canStartRecording: Bool {
        state == .ready
    }

    public static func checking(for mode: AudioInputMode) -> AudioInputReadiness {
        AudioInputReadiness(
            state: .checking,
            title: "\(mode.title) 입력 확인 중",
            detail: "녹음 시작 전에 입력 권한과 가용성을 확인하고 있어요."
        )
    }

    public static func ready(for mode: AudioInputMode) -> AudioInputReadiness {
        AudioInputReadiness(
            state: .ready,
            title: "\(mode.title) 입력 가능",
            detail: mode.detail
        )
    }
}

public enum AudioSourceError: Error, Sendable {
    case permissionDenied
    case screenCapturePermissionDenied
    case systemAudioUnavailable(String)
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
            return "음성 인식 엔진이 아직 준비되지 않았어요."
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
