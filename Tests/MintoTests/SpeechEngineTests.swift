import Foundation
import Testing
@testable import MintoCore

@Suite("음성 인식 엔진 설정")
struct SpeechEngineTests {

    @Test("WhisperKit variant를 사용자용 엔진으로 매핑한다")
    func mapsWhisperVariantsToSpeechEngines() {
        #expect(SpeechEngineID.fromWhisperVariant("openai_whisper-large-v3-v20240930_turbo") == .whisperAccurate)
        #expect(SpeechEngineID.fromWhisperVariant("openai_whisper-medium") == .whisperBalanced)
        #expect(SpeechEngineID.fromWhisperVariant("openai_whisper-small") == .whisperFast)
    }

    @Test("SFSpeechRecognizer는 온디바이스 전용 정책이다")
    func sfSpeechIsOnDeviceOnly() {
        #expect(SpeechEngineID.sfSpeechOnDevice.requiresOnDeviceOnly)
        #expect(!SpeechEngineID.speechAnalyzer.requiresOnDeviceOnly)
        #expect(SpeechEngineID.sfSpeechOnDevice.whisperVariant == nil)
        #expect(!SpeechEngineID.sfSpeechOnDevice.supportsPreviewTranscription)
        #expect(!SpeechEngineID.speechAnalyzer.supportsPreviewTranscription)
    }

    @Test("SFSpeech 상태 확인은 background task에서도 안전하다")
    func sfSpeechAvailabilityCanRunOffMainActor() async {
        let availability = await Task.detached {
            STTService.sfSpeechOnDeviceAvailability()
        }.value

        switch availability {
        case .available, .requiresPermission, .unavailable:
            break
        case .checking:
            Issue.record("SFSpeech 상태 확인은 즉시 판단 가능한 상태를 반환해야 합니다.")
        }
    }

    @Test("legacy selectedModel에서 새 selectedSpeechEngine을 복원한다")
    func restoresEngineFromLegacySelectedModel() {
        let suiteName = "minto-speech-engine-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("openai_whisper-small", forKey: SpeechEnginePreferences.selectedModelKey)

        #expect(SpeechEnginePreferences.selectedEngine(in: defaults) == .whisperFast)

        SpeechEnginePreferences.normalizeLegacyValues(in: defaults)
        #expect(defaults.string(forKey: SpeechEnginePreferences.selectedEngineKey) == SpeechEngineID.whisperFast.rawValue)
    }

    @Test("deprecated Whisper 모델은 기본 엔진으로 마이그레이션한다")
    func migratesDeprecatedWhisperModelToDefaultEngine() {
        let suiteName = "minto-deprecated-engine-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("openai_whisper-tiny", forKey: SpeechEnginePreferences.selectedModelKey)

        SpeechEnginePreferences.normalizeLegacyValues(in: defaults)

        #expect(defaults.string(forKey: SpeechEnginePreferences.selectedModelKey) == SpeechEngineID.defaultEngine.whisperVariant)
        #expect(defaults.string(forKey: SpeechEnginePreferences.selectedEngineKey) == SpeechEngineID.defaultEngine.rawValue)
    }
}
