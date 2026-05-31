import Testing
@testable import MintoCore
import Foundation

/// WhisperKit 통합 테스트는 모델 다운로드가 필요합니다.
/// 수동 실행: RUN_STT_TESTS=1 swift test -c release --filter STTIntegrationTests
@MainActor
@Suite("STT Integration Tests (Manual Only)", .serialized)
struct STTIntegrationTests {

    func makeSineWave(seconds: Int = 5, hz: Float = 440, amplitude: Float = 0.3) -> [Float] {
        let count = 16000 * seconds
        return (0..<count).map { i in
            amplitude * sin(2 * .pi * hz * Float(i) / 16000)
        }
    }

    @Test("whisper-tiny: 모델 다운로드 후 추론 성공")
    func whisperTinyInference() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1" else { return }

        let service = STTService()
        await service.loadModel(variant: "openai_whisper-tiny")

        guard case .loaded = service.modelState else {
            Issue.record("모델 로드 실패: \(service.modelState)")
            return
        }

        let samples = makeSineWave()
        let start = Date()
        let result = try await service.transcribe(pcmSamples: samples)
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 10.0, "추론은 10초 이내에 완료되어야 합니다. 실제: \(elapsed)s")
        _ = result
    }

    @Test("파이프라인: VADProcessor → STTService 연결 경로 동작 확인")
    func pipelineVADToSTT() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1" else { return }

        let service = STTService()
        await service.loadModel(variant: "openai_whisper-tiny")

        guard case .loaded = service.modelState else {
            Issue.record("모델 로드 실패: \(service.modelState)")
            return
        }

        let vad = VADProcessor()
        var receivedChunks: [AudioChunk] = []

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        vad.onChunk = { chunk in
            continuation.yield(chunk)
        }

        let batchSize = 1600

        // 캘리브레이션: 저진폭 신호로 노이즈 플로어 설정 (noiseFloor ≈ -29dB, threshold ≈ -23dB)
        let calibSamples = makeSineWave(seconds: 2, hz: 440, amplitude: 0.05)
        for batchStart in stride(from: 0, to: calibSamples.count, by: batchSize) {
            let end = min(batchStart + batchSize, calibSamples.count)
            vad.process(samples: Array(calibSamples[batchStart..<end]))
        }

        // 스피치: 고진폭 신호로 threshold 초과 → 버퍼가 maxSamples(15s)에 달하면 자동 flush
        let speechSamples = makeSineWave(seconds: 16, hz: 440, amplitude: 0.8)
        for batchStart in stride(from: 0, to: speechSamples.count, by: batchSize) {
            let end = min(batchStart + batchSize, speechSamples.count)
            vad.process(samples: Array(speechSamples[batchStart..<end]))
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            continuation.finish()
        }

        for await chunk in stream {
            receivedChunks.append(chunk)
            continuation.finish()
            break
        }

        #expect(!receivedChunks.isEmpty, "VADProcessor가 적어도 하나의 AudioChunk를 내보내야 합니다")

        if let chunk = receivedChunks.first {
            let result = try await service.transcribe(pcmSamples: chunk.samples)
            print("[Pipeline Smoke] transcribed: '\(result.segment.text)'")
        }
    }
}
