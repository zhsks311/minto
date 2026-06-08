import Foundation
import Testing
@testable import MintoCore

@MainActor
enum STTBenchmarkEngineSupport {
    static let defaultWhisperModel = "openai_whisper-large-v3-v20240930_turbo"

    static var whisperModel: String {
        nonEmptyEnvironmentValue("STT_MODEL") ?? defaultWhisperModel
    }

    static func loadService() async throws -> STTService {
        let service = STTService()
        let requestedEngine = try engineID()

        if requestedEngine.whisperVariant != nil, nonEmptyEnvironmentValue("STT_MODEL") != nil {
            await service.loadModel(variant: whisperModel)
        } else {
            await service.loadEngine(requestedEngine)
        }

        return service
    }

    static func displayName(for service: STTService) -> String {
        if service.speechEngineID.whisperVariant != nil {
            return "\(service.speechEngineID.rawValue) / \(service.modelVariant)"
        }
        return service.speechEngineID.rawValue
    }

    static func metricsMetadata(for service: STTService) -> [String: Any] {
        [
            "engine": service.speechEngineID.rawValue,
            "model": service.speechEngineID.whisperVariant == nil ? "" : service.modelVariant,
            "supports_preview": service.supportsPreviewTranscription,
        ]
    }

    private static func engineID() throws -> SpeechEngineID {
        guard let rawEngine = nonEmptyEnvironmentValue("STT_ENGINE") else {
            return SpeechEngineID.fromWhisperVariant(whisperModel)
        }

        if let engine = SpeechEngineID(rawValue: rawEngine) {
            return engine
        }

        if rawEngine.hasPrefix("openai_whisper-") {
            return SpeechEngineID.fromWhisperVariant(rawEngine)
        }

        throw STTBenchmarkEngineError.invalidEngine(rawEngine)
    }

    private static func nonEmptyEnvironmentValue(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private enum STTBenchmarkEngineError: LocalizedError {
    case invalidEngine(String)

    var errorDescription: String? {
        switch self {
        case .invalidEngine(let value):
            return "지원하지 않는 STT_ENGINE 값입니다: \(value)"
        }
    }
}
