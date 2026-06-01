import Testing
@testable import MintoCore

@Suite("VADProcessor Tests")
struct VADProcessorTests {

    private let frameSize = 1600  // 100ms at 16kHz

    private func calibrate(_ vad: VADProcessor) {
        let calibrationSamples = [Float](repeating: 0.01, count: frameSize)
        for _ in 0..<10 {
            vad.process(samples: calibrationSamples)
        }
    }

    @Test("순수 침묵: 청크 미방출")
    func silentInputDoesNotFlush() async {
        let vad = VADProcessor()
        nonisolated(unsafe) var chunks: [AudioChunk] = []
        vad.onChunk = { chunks.append($0) }

        // All zeros = -∞ dBFS, definitely silent
        let silentSamples = [Float](repeating: 0.0, count: frameSize)
        vad.process(samples: silentSamples)

        // Give VAD time to process
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(chunks.isEmpty, "Silent input should not produce chunks")
    }

    @Test("발화 후 1.5초 침묵: 청크 1개 방출")
    func speechFollowedBySilenceProducesOneChunk() async throws {
        let vad = VADProcessor()
        nonisolated(unsafe) var chunks: [AudioChunk] = []
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()

        vad.onChunk = { chunk in
            chunks.append(chunk)
            continuation.yield(chunk)
        }

        calibrate(vad)

        // Speech: 0.5 amplitude = about -6 dBFS, above -50 threshold
        let speechSamples = [Float](repeating: 0.5, count: 16000)  // 1s speech
        vad.process(samples: speechSamples)

        // Silence: zeros — 24000 samples = 1.5s threshold
        let silentSamples = [Float](repeating: 0.0, count: 24000)
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

    @Test("15초 연속 발화: 최대 청크 분할")
    func continuousSpeechExceedingMaxDurationFlushes() async throws {
        let vad = VADProcessor()
        nonisolated(unsafe) var chunks: [AudioChunk] = []
        vad.onChunk = { chunks.append($0) }

        calibrate(vad)

        // 15s of speech = 240000 samples at 16kHz
        let speechSamples = [Float](repeating: 0.5, count: frameSize)
        for _ in 0..<150 {
            vad.process(samples: speechSamples)
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(!chunks.isEmpty, "Continuous speech over 15s should force flush")
        if let chunk = chunks.first {
            #expect(chunk.durationSeconds <= 15.1, "Chunk should be at most ~15s")
        }
    }

    @Test("ramp-up: 첫 청크는 약 5초에 더 빨리 분할")
    func firstChunkRampsUpFaster() async throws {
        let vad = VADProcessor()
        nonisolated(unsafe) var chunks: [AudioChunk] = []
        vad.onChunk = { chunks.append($0) }

        calibrate(vad)

        // 8s of continuous speech = 80 frames of 100ms.
        // 첫 청크 상한(5s)에서 강제 flush되어야 한다 (15s까지 기다리지 않음).
        let speechSamples = [Float](repeating: 0.5, count: frameSize)
        for _ in 0..<80 {
            vad.process(samples: speechSamples)
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(!chunks.isEmpty, "8s continuous speech should force an early first flush via ramp-up")
        if let first = chunks.first {
            #expect(first.durationSeconds <= 5.1, "First chunk should ramp up at ~5s, not wait for 15s")
            #expect(first.durationSeconds >= 4.9, "First chunk should be ~5s")
        }
    }

    @Test("짧은 침묵-flush 청크는 ramp-up을 소진하지 않는다")
    func silenceFlushedChunkDoesNotConsumeRampUp() async throws {
        let vad = VADProcessor()
        nonisolated(unsafe) var chunks: [AudioChunk] = []
        vad.onChunk = { chunks.append($0) }

        calibrate(vad)

        // 1) 짧은 발화(0.8s) + 침묵 → 침묵 기반 flush (ramp-up 소진하면 안 됨)
        vad.process(samples: [Float](repeating: 0.5, count: 12800))   // 0.8s speech
        vad.process(samples: [Float](repeating: 0.0, count: 24000))   // 1.5s silence → flush
        try? await Task.sleep(nanoseconds: 150_000_000)

        // 2) 이어서 연속 발화 → 첫 강제 분할은 여전히 ~5초여야 한다
        let speechSamples = [Float](repeating: 0.5, count: frameSize)
        for _ in 0..<80 {   // 8s 연속
            vad.process(samples: speechSamples)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)

        // 두 번째 청크(연속 발화의 첫 강제 분할)가 ~5초여야 한다
        #expect(chunks.count >= 2, "Should have the short chunk plus a ramped first continuous chunk")
        if chunks.count >= 2 {
            #expect(chunks[1].durationSeconds <= 5.1,
                    "Ramp-up should survive a silence-flushed chunk and apply at ~5s")
        }
    }

    @Test("reset 후 ramp-up 재적용: 두 번째 녹음도 첫 청크 ~5초")
    func resetReappliesRampUp() async throws {
        let vad = VADProcessor()
        nonisolated(unsafe) var chunks: [AudioChunk] = []
        vad.onChunk = { chunks.append($0) }

        calibrate(vad)
        let speechSamples = [Float](repeating: 0.5, count: frameSize)
        // 첫 녹음: ramp-up 소진
        for _ in 0..<80 { vad.process(samples: speechSamples) }
        try? await Task.sleep(nanoseconds: 200_000_000)

        // 두 번째 녹음 시작 시뮬레이션
        vad.reset()
        try? await Task.sleep(nanoseconds: 50_000_000)
        chunks.removeAll()

        for _ in 0..<80 { vad.process(samples: speechSamples) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(!chunks.isEmpty, "After reset, ramp-up should apply again")
        if let first = chunks.first {
            #expect(first.durationSeconds <= 5.1, "Post-reset first chunk should ramp up at ~5s")
        }
    }
}
