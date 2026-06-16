import Foundation
@preconcurrency import FluidAudio

public struct DiarizedSpeakerSegment: Sendable, Equatable {
    public let speakerId: String
    public let startSeconds: Double
    public let endSeconds: Double

    public init(speakerId: String, startSeconds: Double, endSeconds: Double) {
        self.speakerId = speakerId
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

public protocol SpeakerDiarizationProvider: Sendable {
    var identifier: String { get }
    func diarize(audioFileURL: URL) async throws -> [DiarizedSpeakerSegment]
}

public struct FluidAudioOfflineDiarizationProvider: SpeakerDiarizationProvider {
    public let identifier = "fluidaudio-offline"

    private let config: OfflineDiarizerConfig

    public init(
        config: OfflineDiarizerConfig = .default,
        clusteringThreshold: Double? = nil,
        warmStartFa: Double? = nil,
        minSpeakers: Int? = nil,
        maxSpeakers: Int? = nil,
        exactSpeakerCount: Int? = nil
    ) {
        var resolvedConfig = config
        if let clusteringThreshold {
            resolvedConfig.clustering.threshold = clusteringThreshold
        }
        if let warmStartFa {
            resolvedConfig.clustering.warmStartFa = warmStartFa
        }
        if let exactSpeakerCount {
            resolvedConfig = resolvedConfig.withSpeakers(exactly: exactSpeakerCount)
        } else if minSpeakers != nil || maxSpeakers != nil {
            resolvedConfig = resolvedConfig.withSpeakers(min: minSpeakers, max: maxSpeakers)
        }
        self.config = resolvedConfig
    }

    public func diarize(audioFileURL: URL) async throws -> [DiarizedSpeakerSegment] {
        let startedAt = Date()
        Log.diarization.info(
            "diarization start provider=\(identifier, privacy: .public) threshold=\(config.clustering.threshold, privacy: .public) warmStartFa=\(config.clustering.warmStartFa, privacy: .public)"
        )

        let manager = OfflineDiarizerManager(config: config)
        let result = try await manager.process(audioFileURL)
        let segments = result.segments.map {
            DiarizedSpeakerSegment(
                speakerId: $0.speakerId,
                startSeconds: Double($0.startTimeSeconds),
                endSeconds: Double($0.endTimeSeconds)
            )
        }

        let elapsedSeconds = Date().timeIntervalSince(startedAt)
        let speakerCount = Set(segments.map(\.speakerId)).count
        Log.diarization.info(
            "diarization complete provider=\(identifier, privacy: .public) segments=\(segments.count, privacy: .public) speakers=\(speakerCount, privacy: .public) elapsedSeconds=\(elapsedSeconds, privacy: .public)"
        )
        return segments
    }

    func diarizeWithEmbeddings(audioFileURL: URL) async throws -> [(speakerId: String, embedding: [Float])] {
        var embeddingConfig = config
        embeddingConfig.exposeChunkEmbeddings = true
        let manager = OfflineDiarizerManager(config: embeddingConfig)
        let result = try await manager.process(audioFileURL)
        return (result.chunkEmbeddings ?? []).map { chunkEmbedding in
            (speakerId: chunkEmbedding.speakerId, embedding: chunkEmbedding.embedding256)
        }
    }
}
