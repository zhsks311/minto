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

public protocol SegmentEmbeddingDiarizing: Sendable {
    func diarizeWithSegmentsAndEmbeddings(
        audioFileURL: URL
    ) async throws -> (
        segments: [DiarizedSpeakerSegment],
        embeddings: [(speakerId: String, embedding: [Float])]
    )
}

public struct FluidAudioOfflineDiarizationProvider: SpeakerDiarizationProvider {
    /// FluidAudio Embedding.mlmodelc(256차원) 좌표공간 식별자.
    /// 임베딩 모델 교체 시 값을 bump해 기존 보이스프린트를 매칭에서 제외하고 재등록을 유도한다.
    public static let embeddingModelID = "fluidaudio-offline-embedding-256"

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

    /// import와 저장 finalize가 쓰는 segment+embedding 경로다.
    /// process()가 실제 ML 모델과 오디오를 요구해 기존 diarize처럼 단위테스트로 격리 검증할 수 없으므로 호출부는 프로토콜로 격리한다.
    /// exposeChunkEmbeddings=true는 chunk 임베딩을 추가로 노출할 뿐 segments의 speakerId 클러스터링 결과를 바꾸지 않는다고 가정한다.
    /// FluidAudio 업그레이드 시 이 가정을 재확인해야 한다. 깨지면 centroid가 다른 화자에 붙는 silent regression이 된다.
    public func diarizeWithSegmentsAndEmbeddings(
        audioFileURL: URL
    ) async throws -> (
        segments: [DiarizedSpeakerSegment],
        embeddings: [(speakerId: String, embedding: [Float])]
    ) {
        let startedAt = Date()
        Log.diarization.info(
            "diarization start provider=\(identifier, privacy: .public) threshold=\(config.clustering.threshold, privacy: .public) warmStartFa=\(config.clustering.warmStartFa, privacy: .public)"
        )

        var embeddingConfig = config
        embeddingConfig.exposeChunkEmbeddings = true
        let manager = OfflineDiarizerManager(config: embeddingConfig)
        let result = try await manager.process(audioFileURL)
        let segments = result.segments.map {
            DiarizedSpeakerSegment(
                speakerId: $0.speakerId,
                startSeconds: Double($0.startTimeSeconds),
                endSeconds: Double($0.endTimeSeconds)
            )
        }
        let embeddings = (result.chunkEmbeddings ?? []).map { chunkEmbedding in
            (speakerId: chunkEmbedding.speakerId, embedding: chunkEmbedding.embedding256)
        }

        let elapsedSeconds = Date().timeIntervalSince(startedAt)
        let speakerCount = Set(segments.map(\.speakerId)).count
        Log.diarization.info(
            "diarization complete provider=\(identifier, privacy: .public) segments=\(segments.count, privacy: .public) speakers=\(speakerCount, privacy: .public) embeddings=\(embeddings.count, privacy: .public) elapsedSeconds=\(elapsedSeconds, privacy: .public)"
        )
        return (segments: segments, embeddings: embeddings)
    }
}

extension FluidAudioOfflineDiarizationProvider: SegmentEmbeddingDiarizing {}
