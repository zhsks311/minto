import Testing

#if compiler(>=6.3) && canImport(Speech)
import Foundation
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

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["RUN_SPEECH_ANALYZER_POC"] == "1"
    }
}
