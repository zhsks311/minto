import Foundation

public enum VADEngineID: String, CaseIterable, Sendable, Identifiable {
    case silero
    case energy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .silero:
            return "정밀 감지 (Silero)"
        case .energy:
            return "기본 감지 (Energy)"
        }
    }

    public var subtitle: String {
        switch self {
        case .silero:
            return "음성 인식 모델로 말소리 구간을 찾아요. 회의 전사 누락이 크게 줄어요. (권장)"
        case .energy:
            return "소리 크기로 말소리 구간을 찾아요. 모델 다운로드가 필요 없어요."
        }
    }
}

public enum VADEnginePreferences {
    public static let selectedEngineKey = "selectedVADEngine"

    /// 검증된 조합(Silero + empty repair)의 벤치마크 우위(전사 누락 대폭 감소)로 기본값은 silero다.
    /// 모델 미준비·로드 실패 시 factory가 Energy로 fail-soft 한다.
    public static func selectedEngine(in defaults: UserDefaults = .standard) -> VADEngineID {
        defaults.string(forKey: selectedEngineKey).flatMap(VADEngineID.init(rawValue:)) ?? .silero
    }
}

public enum VoiceActivityDetectorFactory {
    public static func makeDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> any VoiceActivityDetector {
        // 벤치마크/진단용 환경변수는 사용자 설정보다 우선한다.
        let requestedEngine = requestedEngine(environment: environment)
        if !requestedEngine.isEmpty {
            guard requestedEngine == "silero" else {
                return VADProcessor()
            }
            return makeSilero(environment: environment) ?? VADProcessor()
        }

        switch VADEnginePreferences.selectedEngine(in: defaults) {
        case .energy:
            return VADProcessor()
        case .silero:
            return makeSilero(environment: environment) ?? VADProcessor()
        }
    }

    private static func makeSilero(environment: [String: String]) -> SileroVADProcessor? {
        guard let configuration = SileroVADProcessor.Configuration(environment: environment),
              configuration.hasLocalModelBundle else {
            Log.vad.error("Silero requested but local model bundle was not found; falling back to Energy VAD")
            return nil
        }
        return SileroVADProcessor(configuration: configuration)
    }

    private static func requestedEngine(environment: [String: String]) -> String {
        (environment["MINTO_VAD_ENGINE"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
