import Foundation
import Testing
@testable import MintoCore

@Suite("VoiceActivityDetectorFactory Tests")
struct VoiceActivityDetectorFactoryTests {
    @Test("환경값이 없으면 기존 Energy VAD를 사용한다")
    func defaultUsesEnergyVAD() {
        let detector = VoiceActivityDetectorFactory.makeDefault(environment: [:])

        #expect(detector is VADProcessor)
    }

    @Test("Silero 요청이어도 로컬 모델이 없으면 Energy VAD로 fallback한다")
    func sileroWithoutLocalModelFallsBackToEnergyVAD() {
        let detector = VoiceActivityDetectorFactory.makeDefault(environment: [
            "MINTO_VAD_ENGINE": "silero",
            "MINTO_FLUIDAUDIO_MODEL_DIR": "/private/tmp/minto2-missing-silero-model",
        ])

        #expect(detector is VADProcessor)
    }

    @Test("Silero 로컬 모델이 있으면 Silero VAD 후보를 사용한다")
    func sileroWithLocalModelUsesSileroVAD() throws {
        let modelRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto2-silero-factory-\(UUID().uuidString)", isDirectory: true)
        let modelBundle = modelRoot
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("silero-vad", isDirectory: true)
            .appendingPathComponent(SileroVADProcessor.Configuration.modelFileName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelBundle, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: modelRoot)
        }

        let detector = VoiceActivityDetectorFactory.makeDefault(environment: [
            "MINTO_VAD_ENGINE": "silero",
            "MINTO_FLUIDAUDIO_MODEL_DIR": modelRoot.path,
            "MINTO_SILERO_VAD_THRESHOLD": "0.6",
            "MINTO_VAD_MERGE_GAP_SEC": "1.1",
        ])

        let silero = try #require(detector as? SileroVADProcessor)
        #expect(silero.configuration.threshold == 0.6)
        #expect(silero.configuration.mergeGapSeconds == 1.1)
    }
}
