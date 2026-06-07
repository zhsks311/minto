import Foundation

public enum SpeechEngineID: String, CaseIterable, Identifiable, Sendable {
    case whisperAccurate = "whisper_accurate"
    case whisperBalanced = "whisper_balanced"
    case whisperFast = "whisper_fast"
    case speechAnalyzer = "speech_analyzer"
    case sfSpeechOnDevice = "sf_speech_on_device"

    public var id: String { rawValue }

    public static let defaultEngine: SpeechEngineID = .whisperAccurate

    public var title: String {
        switch self {
        case .whisperAccurate: return "회의 정확도 우선"
        case .whisperBalanced: return "균형"
        case .whisperFast: return "빠른 기록"
        case .speechAnalyzer: return "Apple 최신 인식"
        case .sfSpeechOnDevice: return "Apple 온디바이스 받아쓰기"
        }
    }

    public var engineName: String {
        switch self {
        case .whisperAccurate, .whisperBalanced, .whisperFast:
            return "로컬 AI"
        case .speechAnalyzer:
            return "Apple 최신 엔진"
        case .sfSpeechOnDevice:
            return "Apple 온디바이스"
        }
    }

    public var technicalName: String {
        switch self {
        case .whisperAccurate, .whisperBalanced, .whisperFast:
            return "WhisperKit"
        case .speechAnalyzer:
            return "SpeechAnalyzer"
        case .sfSpeechOnDevice:
            return "SFSpeechRecognizer"
        }
    }

    public var description: String {
        switch self {
        case .whisperAccurate:
            return "한국어 회의 권장"
        case .whisperBalanced:
            return "정확도와 속도 균형"
        case .whisperFast:
            return "빠른 초안용"
        case .speechAnalyzer:
            return "macOS 26 이상에서 사용 가능"
        case .sfSpeechOnDevice:
            return "Apple 서버를 쓰지 않음"
        }
    }

    public var memoryNote: String {
        switch self {
        case .whisperAccurate:
            return "RAM 2GB+ 여유 권장"
        case .whisperBalanced:
            return "RAM 1.5GB+ 여유 권장"
        case .whisperFast:
            return "RAM 700MB+ 여유 권장"
        case .speechAnalyzer:
            return "Apple 시스템 리소스 사용"
        case .sfSpeechOnDevice:
            return "Apple 시스템 리소스 사용"
        }
    }

    public var requirementNote: String {
        switch self {
        case .whisperAccurate, .whisperBalanced, .whisperFast:
            return "macOS 14+"
        case .speechAnalyzer:
            return "macOS 26+"
        case .sfSpeechOnDevice:
            return "macOS 10.15+ · 권한과 한국어 asset 필요"
        }
    }

    public var whisperVariant: String? {
        switch self {
        case .whisperAccurate:
            return "openai_whisper-large-v3-v20240930_turbo"
        case .whisperBalanced:
            return "openai_whisper-medium"
        case .whisperFast:
            return "openai_whisper-small"
        case .speechAnalyzer, .sfSpeechOnDevice:
            return nil
        }
    }

    public var supportsPreviewTranscription: Bool {
        switch self {
        case .whisperAccurate, .whisperBalanced, .whisperFast:
            return true
        case .speechAnalyzer, .sfSpeechOnDevice:
            return false
        }
    }

    public var supportsCacheRecovery: Bool {
        whisperVariant != nil
    }

    public var requiresOnDeviceOnly: Bool {
        self == .sfSpeechOnDevice
    }

    public static func fromWhisperVariant(_ variant: String) -> SpeechEngineID {
        switch variant {
        case "openai_whisper-medium":
            return .whisperBalanced
        case "openai_whisper-small":
            return .whisperFast
        default:
            return .whisperAccurate
        }
    }
}

public enum SpeechEngineAvailability: Equatable, Sendable {
    case checking(String)
    case available
    case requiresPermission(String)
    case unavailable(String)

    public var isSelectable: Bool {
        if case .available = self { return true }
        return false
    }

    public var statusText: String {
        switch self {
        case .checking:
            return "확인 중"
        case .available:
            return "사용 가능"
        case .requiresPermission:
            return "권한 필요"
        case .unavailable:
            return "사용 불가"
        }
    }

    public var detailText: String? {
        switch self {
        case .available:
            return nil
        case .checking(let reason):
            return reason
        case .requiresPermission(let reason), .unavailable(let reason):
            return reason
        }
    }
}

public enum SpeechEnginePreferences {
    public static let selectedEngineKey = "selectedSpeechEngine"
    public static let selectedModelKey = "selectedModel"

    private static let deprecatedModelIDs: Set<String> = [
        "openai_whisper-tiny",
        "openai_whisper-base",
        "openai_whisper-large-v3-v20240930_626MB",
        "openai_whisper-large-v3-v20240930_turbo_632MB",
    ]

    public static func selectedEngine(in defaults: UserDefaults = .standard) -> SpeechEngineID {
        if let raw = defaults.string(forKey: selectedEngineKey),
           let engine = SpeechEngineID(rawValue: raw) {
            return engine
        }

        let selectedModel = defaults.string(forKey: selectedModelKey) ?? SpeechEngineID.defaultEngine.whisperVariant!
        return SpeechEngineID.fromWhisperVariant(selectedModel)
    }

    public static func normalizeLegacyValues(in defaults: UserDefaults = .standard) {
        let defaultVariant = SpeechEngineID.defaultEngine.whisperVariant!
        if let selectedModel = defaults.string(forKey: selectedModelKey),
           deprecatedModelIDs.contains(selectedModel) {
            defaults.set(defaultVariant, forKey: selectedModelKey)
            defaults.set(SpeechEngineID.defaultEngine.rawValue, forKey: selectedEngineKey)
            return
        }

        if defaults.string(forKey: selectedEngineKey) == nil {
            let engine = selectedEngine(in: defaults)
            defaults.set(engine.rawValue, forKey: selectedEngineKey)
        }
    }
}
