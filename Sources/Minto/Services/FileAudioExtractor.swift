import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import UniformTypeIdentifiers

public struct FileAudioExtraction: Sendable, Equatable {
    public let durationSeconds: TimeInterval

    public init(durationSeconds: TimeInterval) {
        self.durationSeconds = durationSeconds
    }
}

public struct FileAudioChunk: Sendable, Equatable {
    public let index: Int
    public let estimatedTotalChunks: Int?
    public let samples: [Float]
    public let startSeconds: TimeInterval
    public let durationSeconds: TimeInterval

    public init(
        index: Int,
        estimatedTotalChunks: Int?,
        samples: [Float],
        startSeconds: TimeInterval,
        durationSeconds: TimeInterval
    ) {
        self.index = index
        self.estimatedTotalChunks = estimatedTotalChunks
        self.samples = samples
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }
}

public enum FileAudioExtractionError: LocalizedError, Sendable, Equatable {
    case unsupportedFile
    case noAudioTrack
    case readerFailed(String)
    case invalidAudioFormat
    case noReadableAudio

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "지원하지 않는 파일 형식이에요. 오디오 파일이나 mp4/mov 영상을 선택해 주세요."
        case .noAudioTrack:
            return "이 파일에는 오디오 트랙이 없어요."
        case .readerFailed(let message):
            return "파일을 열 수 없어요. 손상되었거나 지원하지 않는 코덱일 수 있어요. (\(message))"
        case .invalidAudioFormat:
            return "파일 음성 포맷을 처리할 수 없어요."
        case .noReadableAudio:
            return "오디오를 읽지 못했어요. 파일이 손상됐을 수 있어요."
        }
    }
}

protocol MeetingFileAudioExtracting: Sendable {
    /// Emits chunks in source order and awaits each callback before reading the next chunk.
    /// Import use-cases rely on that backpressure for ordered transcript context.
    func extractChunks(
        from url: URL,
        chunkSeconds: TimeInterval,
        onChunk: @MainActor @Sendable @escaping (FileAudioChunk) async throws -> Void
    ) async throws -> FileAudioExtraction
}

public struct FileAudioExtractor: MeetingFileAudioExtracting {
    public static let supportedContentTypes: [UTType] = [
        .audio,
        .movie,
        .mpeg4Movie,
        UTType(filenameExtension: "m4a") ?? .audio,
        UTType(filenameExtension: "mp3") ?? .audio,
        UTType(filenameExtension: "wav") ?? .audio,
    ]

    public init() {}

    public func extractChunks(
        from url: URL,
        chunkSeconds: TimeInterval,
        onChunk: @MainActor @Sendable @escaping (FileAudioChunk) async throws -> Void
    ) async throws -> FileAudioExtraction {
        let isSupported = Self.supportedContentTypes.contains { url.conforms(to: $0) }
        guard isSupported else { throw FileAudioExtractionError.unsupportedFile }

        let extractionTask = Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let tracks: [AVAssetTrack]
            do {
                tracks = try await asset.loadTracks(withMediaType: .audio)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FileAudioExtractionError.readerFailed(error.localizedDescription)
            }
            guard let track = tracks.first else {
                throw FileAudioExtractionError.noAudioTrack
            }
            let duration: CMTime
            do {
                duration = try await asset.load(.duration)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FileAudioExtractionError.readerFailed(error.localizedDescription)
            }
            let assetDuration = CMTimeGetSeconds(duration)
            let fallbackDuration = assetDuration.isFinite && assetDuration > 0 ? assetDuration : 0
            let chunkSize = max(1, Int((max(1, chunkSeconds) * STTAudioUtilities.sampleRate).rounded()))
            let estimatedTotalChunks = Self.estimatedChunkCount(durationSeconds: fallbackDuration, chunkSeconds: chunkSeconds)

            let decodedDuration = try await Self.readChunks(
                asset: asset,
                track: track,
                chunkSize: chunkSize,
                estimatedTotalChunks: estimatedTotalChunks,
                onChunk: onChunk
            )
            guard decodedDuration > 0 else {
                throw FileAudioExtractionError.noReadableAudio
            }
            return FileAudioExtraction(durationSeconds: max(fallbackDuration, decodedDuration))
        }
        return try await withTaskCancellationHandler {
            try await extractionTask.value
        } onCancel: {
            extractionTask.cancel()
        }
    }

    static func makeChunks(samples: [Float], chunkSeconds: TimeInterval, sampleRate: Double) -> [FileAudioChunk] {
        guard !samples.isEmpty, chunkSeconds > 0, sampleRate > 0 else { return [] }
        let chunkSize = max(1, Int((chunkSeconds * sampleRate).rounded()))
        var accumulator = FileAudioChunkAccumulator(
            chunkSize: chunkSize,
            sampleRate: sampleRate,
            estimatedTotalChunks: Int(ceil(Double(samples.count) / Double(chunkSize)))
        )
        var chunks = accumulator.append(samples)
        chunks.append(contentsOf: accumulator.finish())
        return chunks
    }

    private static func readChunks(
        asset: AVAsset,
        track: AVAssetTrack,
        chunkSize: Int,
        estimatedTotalChunks: Int?,
        onChunk: @MainActor @Sendable @escaping (FileAudioChunk) async throws -> Void
    ) async throws -> TimeInterval {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw FileAudioExtractionError.readerFailed(error.localizedDescription)
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw FileAudioExtractionError.invalidAudioFormat
        }
        reader.add(output)

        guard reader.startReading() else {
            throw FileAudioExtractionError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        var accumulator = FileAudioChunkAccumulator(
            chunkSize: chunkSize,
            sampleRate: STTAudioUtilities.sampleRate,
            estimatedTotalChunks: estimatedTotalChunks
        )

        while reader.status == .reading {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            let decoded = try decodeMonoFloatSamples(from: sampleBuffer)
            let resampled = resample(decoded.samples, sourceRate: decoded.sampleRate)
            for chunk in accumulator.append(resampled) {
                try await emit(chunk, reader: reader, onChunk: onChunk)
            }
        }

        if reader.status == .failed || reader.status == .cancelled {
            throw FileAudioExtractionError.readerFailed(reader.error?.localizedDescription ?? "\(reader.status.rawValue)")
        }

        for chunk in accumulator.finish() {
            try await emit(chunk, reader: reader, onChunk: onChunk)
        }
        return accumulator.emittedDurationSeconds
    }

    private static func emit(
        _ chunk: FileAudioChunk,
        reader: AVAssetReader,
        onChunk: @MainActor @Sendable @escaping (FileAudioChunk) async throws -> Void
    ) async throws {
        do {
            try await onChunk(chunk)
        } catch {
            reader.cancelReading()
            throw error
        }
    }

    private static func decodeMonoFloatSamples(from sampleBuffer: CMSampleBuffer) throws -> SourceSamples {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw FileAudioExtractionError.invalidAudioFormat
        }

        let asbd = streamDescription.pointee
        let channelCount = max(1, Int(asbd.mChannelsPerFrame))
        let sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : STTAudioUtilities.sampleRate
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw FileAudioExtractionError.invalidAudioFormat
        }

        let byteLength = CMBlockBufferGetDataLength(blockBuffer)
        guard byteLength >= MemoryLayout<Float>.size else {
            return SourceSamples(samples: [], sampleRate: sampleRate)
        }

        var data = Data(count: byteLength)
        let status = data.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let baseAddress = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: byteLength,
                destination: baseAddress
            )
        }
        guard status == kCMBlockBufferNoErr else {
            throw FileAudioExtractionError.readerFailed("buffer copy failed: \(status)")
        }

        let sampleCount = byteLength / MemoryLayout<Float>.size
        let mono = data.withUnsafeBytes { rawBuffer -> [Float] in
            let floats = rawBuffer.bindMemory(to: Float.self)
            let frameCount = sampleCount / channelCount
            var output: [Float] = []
            output.reserveCapacity(frameCount)
            for frameIndex in 0..<frameCount {
                let frameOffset = frameIndex * channelCount
                var sum: Float = 0
                for channelIndex in 0..<channelCount {
                    sum += floats[frameOffset + channelIndex]
                }
                output.append(sum / Float(channelCount))
            }
            return output
        }
        return SourceSamples(samples: mono, sampleRate: sampleRate)
    }

    static func resample(
        _ samples: [Float],
        sourceRate: Double,
        targetRate: Double = STTAudioUtilities.sampleRate
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard sourceRate > 0, targetRate > 0 else { return samples }
        guard abs(sourceRate - targetRate) >= 1 else { return samples }

        let outputCount = max(1, Int((Double(samples.count) * targetRate / sourceRate).rounded()))
        guard outputCount > 1, samples.count > 1 else { return [samples[0]] }

        var output = [Float]()
        output.reserveCapacity(outputCount)
        for outputIndex in 0..<outputCount {
            let sourcePosition = Double(outputIndex) * sourceRate / targetRate
            let lower = min(max(0, Int(sourcePosition.rounded(.down))), samples.count - 1)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lower))
            output.append(samples[lower] + (samples[upper] - samples[lower]) * fraction)
        }
        return output
    }

    private static func estimatedChunkCount(durationSeconds: TimeInterval, chunkSeconds: TimeInterval) -> Int? {
        guard durationSeconds.isFinite, durationSeconds > 0, chunkSeconds > 0 else { return nil }
        return max(1, Int(ceil(durationSeconds / chunkSeconds)))
    }

    private struct SourceSamples {
        let samples: [Float]
        let sampleRate: Double
    }

    private struct FileAudioChunkAccumulator {
        let chunkSize: Int
        let sampleRate: Double
        let estimatedTotalChunks: Int?
        private var buffer: [Float] = []
        private var consumedBufferCount = 0
        private var emittedSampleCount = 0
        private var emittedChunkCount = 0

        var emittedDurationSeconds: TimeInterval {
            Double(emittedSampleCount) / sampleRate
        }

        init(chunkSize: Int, sampleRate: Double, estimatedTotalChunks: Int?) {
            self.chunkSize = max(1, chunkSize)
            self.sampleRate = sampleRate > 0 ? sampleRate : STTAudioUtilities.sampleRate
            self.estimatedTotalChunks = estimatedTotalChunks
        }

        mutating func append(_ samples: [Float]) -> [FileAudioChunk] {
            guard !samples.isEmpty else { return [] }
            buffer.append(contentsOf: samples)
            return drain(keepRemainder: true)
        }

        mutating func finish() -> [FileAudioChunk] {
            drain(keepRemainder: false)
        }

        private mutating func drain(keepRemainder: Bool) -> [FileAudioChunk] {
            var chunks: [FileAudioChunk] = []
            while buffer.count - consumedBufferCount >= chunkSize {
                chunks.append(makeChunk(sampleCount: chunkSize))
                compactIfNeeded()
            }
            if !keepRemainder, buffer.count > consumedBufferCount {
                chunks.append(makeChunk(sampleCount: buffer.count - consumedBufferCount))
                compactConsumed()
            }
            return chunks
        }

        private mutating func makeChunk(sampleCount: Int) -> FileAudioChunk {
            let start = consumedBufferCount
            let end = start + sampleCount
            let chunkSamples = Array(buffer[start..<end])
            let chunk = FileAudioChunk(
                index: emittedChunkCount,
                estimatedTotalChunks: estimatedTotalChunks,
                samples: chunkSamples,
                startSeconds: Double(emittedSampleCount) / sampleRate,
                durationSeconds: Double(sampleCount) / sampleRate
            )
            consumedBufferCount = end
            emittedSampleCount += sampleCount
            emittedChunkCount += 1
            return chunk
        }

        private mutating func compactIfNeeded() {
            if consumedBufferCount >= chunkSize * 4 {
                compactConsumed()
            }
        }

        private mutating func compactConsumed() {
            guard consumedBufferCount > 0 else { return }
            buffer.removeFirst(consumedBufferCount)
            consumedBufferCount = 0
        }
    }
}

private extension URL {
    func conforms(to type: UTType) -> Bool {
        guard let fileType = UTType(filenameExtension: pathExtension) else { return false }
        return fileType.conforms(to: type)
    }
}
