import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("SpeechAnalyzer Streaming PoC")
struct SpeechAnalyzerStreamingEngineTests {

    @Test("SpeechAnalyzer streaming 엔진은 제품 기본 경로 밖의 hidden PoC다")
    func speechAnalyzerStreamingEngineIsHiddenPoC() {
        #expect(SpeechEngineID.speechAnalyzer.supportsTrueStreaming == false)
        #expect(TranscriptionCoordinatorPlan.make(engineID: .speechAnalyzer).route == .oneShotVADChunks(rollingPreview: false))
    }

    @Test("SpeechAnalyzer streaming session smoke")
    func speechAnalyzerStreamingSessionSmoke() async throws {
        guard Self.isEnabled else { return }

        #if compiler(>=6.3) && canImport(Speech)
        guard #available(macOS 26.0, *) else {
            Issue.record("SpeechAnalyzer streaming은 macOS 26 이상에서만 실행할 수 있다")
            return
        }

        let availability = await SpeechAnalyzerSTTEngine.availability()
        guard availability.isSelectable else {
            print("[SpeechAnalyzerStreaming] skip smoke: \(availability.detailText ?? "\(availability)")")
            return
        }

        let engine = SpeechAnalyzerStreamingEngine()
        let coordinator = TranscriptionCoordinator(
            plan: TranscriptionCoordinatorPlan.make(
                capabilities: TranscriptionCoordinatorCapabilities(
                    supportsPreviewTranscription: false,
                    supportsTrueStreaming: true
                )
            ),
            onStreamingEvent: { _ in }
        )

        try await coordinator.startStreaming(engine: engine)
        for chunk in Self.sineWaveChunks(seconds: 2, chunkSeconds: 0.25) {
            try await coordinator.acceptStreamingSamples(chunk)
        }
        try await coordinator.finishStreaming()

        #expect(coordinator.metrics.acceptedSampleCount == 32_000)
        #else
        Issue.record("현재 SDK에서 SpeechAnalyzer streaming API를 사용할 수 없다")
        #endif
    }

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["RUN_SPEECH_ANALYZER_STREAMING_POC"] == "1"
    }

    private static func sineWaveChunks(
        seconds: Int,
        chunkSeconds: Double,
        hz: Float = 440,
        amplitude: Float = 0.3
    ) -> [[Float]] {
        let sampleRate = 16_000
        let totalCount = sampleRate * seconds
        let chunkCount = Int(Double(sampleRate) * chunkSeconds)
        let samples = (0..<totalCount).map { index in
            amplitude * sin(2 * .pi * hz * Float(index) / Float(sampleRate))
        }
        return stride(from: 0, to: samples.count, by: chunkCount).map { start in
            Array(samples[start..<min(start + chunkCount, samples.count)])
        }
    }
}
