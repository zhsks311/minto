import AVFoundation
import Foundation
import Testing
@testable import MintoCore

@Suite("SileroModelFrameAccumulator")
struct SileroModelFrameAccumulatorTests {
    @Test("프레임 미만 입력은 모았다가 채워질 때 정확히 프레임 크기로 내보낸다")
    func accumulatesSmallBuffersIntoExactFrames() {
        var accumulator = SileroModelFrameAccumulator(frameSize: 4_096)

        // 라이브 마이크 패턴: 48kHz 탭 4096프레임 → 16kHz 변환 후 ~1365샘플
        #expect(accumulator.append([Float](repeating: 0.1, count: 1_365)).isEmpty)
        #expect(accumulator.append([Float](repeating: 0.2, count: 1_365)).isEmpty)
        #expect(accumulator.append([Float](repeating: 0.3, count: 1_365)).isEmpty)  // 4095 < 4096

        let frames = accumulator.append([Float](repeating: 0.4, count: 1_365))
        #expect(frames.count == 1)
        #expect(frames[0].count == 4_096)
        // 경계 보존: 첫 프레임은 입력 순서를 그대로 잇는다
        #expect(frames[0][0] == 0.1)
        #expect(frames[0][4_095] == 0.4)
        #expect(accumulator.pendingCount == 1_365 * 4 - 4_096)
    }

    @Test("큰 입력은 한 번에 여러 프레임으로 잘린다")
    func splitsLargeInputIntoMultipleFrames() {
        var accumulator = SileroModelFrameAccumulator(frameSize: 4_096)

        let frames = accumulator.append([Float](repeating: 0.5, count: 4_096 * 3 + 100))

        #expect(frames.count == 3)
        #expect(frames.allSatisfy { $0.count == 4_096 })
        #expect(accumulator.pendingCount == 100)
    }

    @Test("reset은 잔여를 비운다")
    func resetClearsPending() {
        var accumulator = SileroModelFrameAccumulator(frameSize: 4_096)
        _ = accumulator.append([Float](repeating: 0.1, count: 1_000))

        accumulator.reset()

        #expect(accumulator.pendingCount == 0)
        #expect(accumulator.append([Float](repeating: 0.2, count: 4_096)).count == 1)
    }
}

/// 실제 Silero 모델 + 실제 음성으로 라이브 마이크 버퍼 패턴(~85ms 단위)을 재현하는 회귀 테스트.
/// 모델 캐시와 음성 wav가 필요해 환경변수로 게이트한다:
///   RUN_SILERO_LIVE_VAD=1 SILERO_LIVE_VAD_WAV=/path/to/speech.wav
@Suite("Silero 라이브 스트리밍 회귀")
struct SileroLiveStreamingRegressionTests {
    @Test(
        "마이크 크기 버퍼를 흘려도 음성 청크가 방출된다",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_SILERO_LIVE_VAD"] == "1")
    )
    func emitsChunksFromMicSizedBuffers() async throws {
        let environment = ProcessInfo.processInfo.environment
        let wavPath = try #require(environment["SILERO_LIVE_VAD_WAV"])
        let configuration = try #require(SileroVADProcessor.Configuration(environment: environment))
        try #require(configuration.hasLocalModelBundle, "Silero 모델 캐시가 필요합니다")

        let file = try AVAudioFile(forReading: URL(fileURLWithPath: wavPath))
        let format = file.processingFormat
        try #require(format.sampleRate == 16_000, "16kHz 음성 wav가 필요합니다")
        let frameCount = min(AVAudioFrameCount(file.length), AVAudioFrameCount(30 * 16_000))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        try file.read(into: buffer, frameCount: frameCount)
        let channel = try #require(buffer.floatChannelData?[0])
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))

        let processor = SileroVADProcessor(configuration: configuration)
        let counter = ChunkCounter()
        processor.onChunk = { _ in counter.add(final: true) }
        processor.onPreviewChunk = { _ in counter.add(final: false) }

        // 라이브 마이크와 동일한 ~85ms(1365샘플) 버퍼로 흘린다.
        var offset = 0
        while offset < samples.count {
            let end = min(offset + 1_365, samples.count)
            processor.process(samples: Array(samples[offset..<end]))
            offset = end
        }
        let flushed = await processor.flushPending()

        // 콜백은 main queue로 전달된다 — 잠시 양보 후 집계.
        for _ in 0..<200 {
            if counter.total > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // flush 1개로는 통과시키지 않는다 — 라이브 증상은 "녹음 중 프리뷰/최종이 전혀 없음"이므로
        // 스트리밍 중 방출(counter)이 0이면 회귀다. 수치는 진단용으로 메시지에 남긴다(원문 없음).
        print("[silero-live-probe] finals+previews=\(counter.total) flushed=\(flushed != nil)")
        #expect(counter.total > 0, "30초 실제 음성에서 스트리밍 청크 0개면 회귀 (flushed=\(flushed != nil))")
    }
}

private final class ChunkCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var finals = 0
    private var previews = 0

    var total: Int {
        lock.withLock { finals + previews }
    }

    func add(final: Bool) {
        lock.withLock {
            if final { finals += 1 } else { previews += 1 }
        }
    }
}

@Suite("Silero 모델 번들 완전성")
struct SileroModelBundleCompletenessTests {
    private func bundleURL(in modelDirectory: URL) -> URL {
        modelDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("silero-vad", isDirectory: true)
            .appendingPathComponent("silero-vad-unified-256ms-v6.0.0.mlmodelc", isDirectory: true)
    }

    private func makeConfiguration(modelDirectory: URL) throws -> SileroVADProcessor.Configuration {
        try #require(SileroVADProcessor.Configuration(environment: ["MINTO_FLUIDAUDIO_MODEL_DIR": modelDirectory.path]))
    }

    @Test(".mlmodelc 디렉터리만 있고 coremldata.bin이 없으면 미준비로 본다(부분 다운로드)")
    func directoryWithoutCoremldataIsNotReady() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("minto-vad-test-\(UUID().uuidString)", isDirectory: true)
        let bundle = bundleURL(in: tempRoot)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let configuration = try makeConfiguration(modelDirectory: tempRoot)
        #expect(configuration.hasLocalModelBundle == false)
    }

    @Test("coremldata.bin이 0바이트면 미준비로 본다(손상)")
    func emptyCoremldataIsNotReady() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("minto-vad-test-\(UUID().uuidString)", isDirectory: true)
        let bundle = bundleURL(in: tempRoot)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bundle.appendingPathComponent("coremldata.bin").path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let configuration = try makeConfiguration(modelDirectory: tempRoot)
        #expect(configuration.hasLocalModelBundle == false)
    }

    @Test("coremldata.bin이 비어있지 않게 존재하면 준비됨으로 본다")
    func nonEmptyCoremldataIsReady() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("minto-vad-test-\(UUID().uuidString)", isDirectory: true)
        let bundle = bundleURL(in: tempRoot)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: bundle.appendingPathComponent("coremldata.bin").path,
            contents: Data([0x01, 0x02, 0x03])
        )
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let configuration = try makeConfiguration(modelDirectory: tempRoot)
        #expect(configuration.hasLocalModelBundle == true)
    }
}
