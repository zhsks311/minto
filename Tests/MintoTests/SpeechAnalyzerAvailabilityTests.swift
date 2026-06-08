import Testing
import Foundation
@testable import MintoCore

#if compiler(>=6.3) && canImport(Speech)
import Speech
#endif

@Suite("SpeechAnalyzer Availability PoC")
struct SpeechAnalyzerAvailabilityTests {
    @Test("SpeechAnalyzer progressive transcriber 구성 smoke")
    func speechAnalyzerProgressiveTranscriberSmoke() async throws {
        guard Self.isEnabled else { return }

        #if compiler(>=6.3) && canImport(Speech)
        guard #available(macOS 26.0, *) else {
            return
        }

        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: "ko-KR"),
            preset: .progressiveTranscription
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        #expect(transcriber.selectedLocales.map(\.identifier) == ["ko_KR"])
        #expect(String(describing: analyzer) == "Speech.SpeechAnalyzer")
        #endif
    }

    @Test("SpeechAnalyzer Korean locale support probe")
    func koreanLocaleSupportProbe() async throws {
        guard Self.isEnabled else { return }

        #if compiler(>=6.3) && canImport(Speech)
        guard #available(macOS 26.0, *) else {
            return
        }

        let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ko-KR"))
        let supportedLocales = await SpeechTranscriber.supportedLocales
        let installedLocales = await SpeechTranscriber.installedLocales

        print("[SpeechAnalyzer] isAvailable=\(SpeechTranscriber.isAvailable)")
        print("[SpeechAnalyzer] ko-KR supported=\(String(describing: supportedLocale?.identifier))")
        print("[SpeechAnalyzer] supportedLocales=\(supportedLocales.map(\.identifier).joined(separator: ","))")
        print("[SpeechAnalyzer] installedLocales=\(installedLocales.map(\.identifier).joined(separator: ","))")

        #expect(SpeechTranscriber.isAvailable)
        #endif
    }

    @MainActor
    @Test("SpeechAnalyzer 파일 전사 smoke")
    func speechAnalyzerFileTranscriptionSmoke() async throws {
        guard Self.isEnabled else { return }

        #if compiler(>=6.3) && canImport(Speech)
        guard #available(macOS 26.0, *) else {
            return
        }

        let service = STTService()
        await service.loadEngine(.speechAnalyzer)

        guard case .loaded = service.modelState else {
            Issue.record("SpeechAnalyzer 로드 실패: \(service.modelState)")
            return
        }

        let samples = Self.sineWave(seconds: 2)
        let result = try await service.transcribe(pcmSamples: samples)

        #expect(result.isFinal)
        #endif
    }

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["RUN_SPEECH_ANALYZER_POC"] == "1"
    }

    private static func sineWave(seconds: Int, hz: Float = 440, amplitude: Float = 0.3) -> [Float] {
        let sampleRate = 16_000
        let count = sampleRate * seconds
        return (0..<count).map { index in
            amplitude * sin(2 * .pi * hz * Float(index) / Float(sampleRate))
        }
    }
}
