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
        case .whisperBalanced: return "균형 모드"
        case .whisperFast: return "빠른 초안"
        case .speechAnalyzer: return "Apple 최신 인식"
        case .sfSpeechOnDevice: return "개인정보 우선 받아쓰기"
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
            return "대부분의 한국어 회의에 권장"
        case .whisperBalanced:
            return "긴 회의에서 속도와 품질 절충"
        case .whisperFast:
            return "임시 기록과 빠른 확인용"
        case .speechAnalyzer:
            return "macOS 26+ Apple 최신 엔진"
        case .sfSpeechOnDevice:
            return "Apple 서버 없이 기기에서 처리"
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

    public var choiceBadge: String {
        switch self {
        case .whisperAccurate:
            return "추천"
        case .whisperBalanced:
            return "절충"
        case .whisperFast:
            return "속도"
        case .speechAnalyzer:
            return "최신"
        case .sfSpeechOnDevice:
            return "개인정보"
        }
    }

    public var bestFor: String {
        switch self {
        case .whisperAccurate:
            return "회의록 품질이 가장 중요할 때"
        case .whisperBalanced:
            return "품질은 유지하면서 부담을 줄이고 싶을 때"
        case .whisperFast:
            return "정확도보다 빠른 초안이 먼저 필요할 때"
        case .speechAnalyzer:
            return "macOS 26 이상에서 Apple 최신 인식을 시험할 때"
        case .sfSpeechOnDevice:
            return "Apple 서버 없이 기기 안에서만 처리하고 싶을 때"
        }
    }

    public var caution: String {
        switch self {
        case .whisperAccurate:
            return "가장 무겁지만 기본 선택으로 가장 안전합니다."
        case .whisperBalanced:
            return "전문용어가 많은 회의는 정확도 우선이 낫습니다."
        case .whisperFast:
            return "회의록 최종본은 교정 확인이 필요합니다."
        case .speechAnalyzer:
            return "OS와 한국어 언어 파일 상태에 따라 비활성화될 수 있습니다."
        case .sfSpeechOnDevice:
            return "권한, 받아쓰기 설정, 한국어 언어 파일 상태에 영향을 받습니다."
        }
    }

    public var choiceChips: [String] {
        switch self {
        case .whisperAccurate:
            return ["품질 높음", "RAM 2GB+"]
        case .whisperBalanced:
            return ["품질/속도 절충", "RAM 1.5GB+"]
        case .whisperFast:
            return ["가벼움", "초안용"]
        case .speechAnalyzer:
            return ["Apple 엔진", "macOS 26+"]
        case .sfSpeechOnDevice:
            return ["서버 전송 없음", "권한/언어 파일"]
        }
    }

    public var requirementNote: String {
        switch self {
        case .whisperAccurate, .whisperBalanced, .whisperFast:
            return "macOS 14+"
        case .speechAnalyzer:
            return "macOS 26+"
        case .sfSpeechOnDevice:
            return "macOS 10.15+ · 권한과 한국어 언어 파일 필요"
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
