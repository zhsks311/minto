import Foundation

public enum VoiceActivityDetectorFactory {
    public static func makeDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any VoiceActivityDetector {
        guard requestedEngine(environment: environment) == "silero" else {
            return VADProcessor()
        }

        guard let configuration = SileroVADProcessor.Configuration(environment: environment),
              configuration.hasLocalModelBundle else {
            fputs("[VAD] Silero requested but local model bundle was not found; falling back to Energy VAD\n", stderr)
            return VADProcessor()
        }

        return SileroVADProcessor(configuration: configuration)
    }

    private static func requestedEngine(environment: [String: String]) -> String {
        (environment["MINTO_VAD_ENGINE"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
