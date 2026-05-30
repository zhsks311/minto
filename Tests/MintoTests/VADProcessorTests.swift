import Testing
@testable import MintoCore

@Suite("VADProcessor Tests")
struct VADProcessorTests {

    @Test("순수 침묵: 청크 미방출")
    func silentInputDoesNotFlush() async {
        let vad = VADProcessor()
        nonisolated(unsafe) var chunks: [AudioChunk] = []
        vad.onChunk = { chunks.append($0) }

        // All zeros = -∞ dBFS, definitely silent
        let silentSamples = [Float](repeating: 0.0, count: 1600)  // 100ms at 16kHz
        vad.process(samples: silentSamples)

        // Give VAD time to process
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(chunks.isEmpty, "Silent input should not produce chunks")
    }

    @Test("발화 후 300ms 침묵: 청크 1개 방출")
    func speechFollowedBySilenceProducesOneChunk() async throws {
        let vad = VADProcessor()
        nonisolated(unsafe) var chunks: [AudioChunk] = []
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()

        vad.onChunk = { chunk in
            chunks.append(chunk)
            continuation.yield(chunk)
        }

        // Speech: 0.5 amplitude = about -6 dBFS, above -50 threshold
        let speechSamples = [Float](repeating: 0.5, count: 16000)  // 1s speech
        vad.process(samples: speechSamples)

        // Silence: zeros — 8000 samples = 0.5s > 300ms (4800 sample threshold)
        let silentSamples = [Float](repeating: 0.0, count: 8000)
        vad.process(samples: silentSamples)

        // 2초 후 스트림 강제 종료 — for await가 무한 대기하지 않도록
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            continuation.finish()
        }

        var received = false
        for await _ in stream {
            received = true
            continuation.finish()
            break
        }

        #expect(received, "Should emit exactly one chunk after speech + silence")
        #expect(chunks.count == 1)
    }

    @Test("5초 초과 연속 발화: 최대 청크 분할")
    func continuousSpeechExceedingMaxDurationFlushes() async throws {
        let vad = VADProcessor()
        nonisolated(unsafe) var chunks: [AudioChunk] = []
        vad.onChunk = { chunks.append($0) }

        // More than 5s of speech = 80001 samples at 16kHz
        let speechSamples = [Float](repeating: 0.5, count: 80001)
        vad.process(samples: speechSamples)

        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(!chunks.isEmpty, "Continuous speech over 5s should force flush")
        #expect(chunks[0].durationSeconds <= 5.1, "Chunk should be at most ~5s")
    }
}
