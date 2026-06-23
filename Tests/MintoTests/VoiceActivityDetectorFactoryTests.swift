import Foundation
import Testing
@testable import MintoCore

@Suite("VoiceActivityDetectorFactory Tests")
struct VoiceActivityDetectorFactoryTests {
    @Test("환경값이 없으면 사용자 설정을 따르고, 모델이 없으면 Energy VAD로 fallback한다")
    func defaultFollowsPreferenceAndFallsBackWithoutModel() {
        // 설정 기본값(silero)이라도 모델 경로가 비어 있으면 Energy로 내려간다.
        let detector = VoiceActivityDetectorFactory.makeDefault(
            environment: ["MINTO_FLUIDAUDIO_MODEL_DIR": "/private/tmp/minto2-missing-silero-\(UUID().uuidString)"],
            defaults: InMemoryUserDefaults()
        )

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
        // 완전한 번들로 인식되려면 coremldata.bin(비어있지 않음)이 있어야 한다(부분 다운로드 방어).
        FileManager.default.createFile(
            atPath: modelBundle.appendingPathComponent("coremldata.bin").path,
            contents: Data([0x01])
        )
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
