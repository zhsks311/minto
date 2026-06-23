import CoreML
import Foundation
@preconcurrency import FluidAudio

public protocol StreamingSpeakerDiarizationProvider: Sendable {
    func start(preEnrolled: [Voiceprint]) async throws
    func process(samples: [Float], sourceSampleRate: Double) async throws -> [DiarizedSpeakerSegment]
    func finish() async throws -> [DiarizedSpeakerSegment]
}

public actor FluidAudioLSEENDStreamingProvider: StreamingSpeakerDiarizationProvider {
    public let identifier = "fluidaudio-lseend-streaming"

    private let variant: LSEENDVariant
    private let stepSize: LSEENDStepSize
    private let cacheDirectory: URL?
    private let diarizer: LSEENDDiarizer

    public init(
        variant: LSEENDVariant = .dihard3,
        stepSize: LSEENDStepSize = .step100ms,
        cacheDirectory: URL? = nil
    ) {
        self.variant = variant
        self.stepSize = stepSize
        self.cacheDirectory = cacheDirectory
        self.diarizer = LSEENDDiarizer()
    }

    public func start(preEnrolled: [Voiceprint]) async throws {
        let variantName = String(describing: variant)
        let stepName = String(describing: stepSize)
        Log.diarization.info(
            "streaming diarization start provider=\(self.identifier, privacy: .public) variant=\(variantName, privacy: .public) step=\(stepName, privacy: .public) preEnrolled=\(preEnrolled.count, privacy: .public)"
        )

        do {
            try await diarizer.initialize(
                variant: variant,
                stepSize: stepSize,
                cacheDirectory: cacheDirectory,
                computeUnits: .cpuOnly
            )

            // Voiceprint stores an embedding centroid only. LS-EEND enrollment requires
            // raw enrollment audio before the first streamed audio chunk, so Phase 1 skips it.
            let skippedEnrollments = preEnrolled.count
            Log.diarization.info(
                "streaming diarization ready provider=\(self.identifier, privacy: .public) targetSampleRate=\(self.diarizer.targetSampleRate ?? 0, privacy: .public) speakers=\(self.diarizer.numSpeakers ?? 0, privacy: .public) skippedEnrollments=\(skippedEnrollments, privacy: .public)"
            )
        } catch {
            logFailure(operation: "start", error: error)
            throw error
        }
    }

    public func process(
        samples: [Float],
        sourceSampleRate: Double
    ) async throws -> [DiarizedSpeakerSegment] {
        guard !samples.isEmpty else {
            return []
        }

        do {
            guard let update = try diarizer.process(
                samples: samples,
                sourceSampleRate: sourceSampleRate
            ) else {
                return []
            }
            return Self.toDiarizedSegments(update)
        } catch {
            logFailure(
                operation: "process",
                error: error,
                sampleCount: samples.count,
                sourceSampleRate: sourceSampleRate
            )
            throw error
        }
    }

    public func finish() async throws -> [DiarizedSpeakerSegment] {
        Log.diarization.info(
            "streaming diarization finish start provider=\(self.identifier, privacy: .public)"
        )

        do {
            let pendingTentativeSegments = diarizer.timeline.speakers.values
                .flatMap { $0.tentativeSegments }
                .sorted()
            let update = try diarizer.finalizeSession()
            let segments = if let update {
                Self.toDiarizedSegments(update)
            } else {
                Self.toDiarizedSegments(pendingTentativeSegments)
            }
            Log.diarization.info(
                "streaming diarization finish complete provider=\(self.identifier, privacy: .public) segments=\(segments.count, privacy: .public)"
            )
            return segments
        } catch {
            logFailure(operation: "finish", error: error)
            throw error
        }
    }

    static func toDiarizedSegments(_ update: DiarizerTimelineUpdate) -> [DiarizedSpeakerSegment] {
        toDiarizedSegments(update.finalizedSegments + update.tentativeSegments)
    }

    private static func toDiarizedSegments(_ segments: [DiarizerSegment]) -> [DiarizedSpeakerSegment] {
        segments.map { segment in
            DiarizedSpeakerSegment(
                speakerId: segment.speakerLabel,
                startSeconds: Double(segment.startTime),
                endSeconds: Double(segment.endTime)
            )
        }
    }

    private func logFailure(
        operation: String,
        error: Error,
        sampleCount: Int = 0,
        sourceSampleRate: Double = 0
    ) {
        let errorCase = Self.errorCase(error)
        let nsError = error as NSError
        Log.diarization.error(
            "streaming diarization failed provider=\(self.identifier, privacy: .public) operation=\(operation, privacy: .public) samples=\(sampleCount, privacy: .public) sourceSampleRate=\(sourceSampleRate, privacy: .public) error=\(errorCase, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
        )
    }

    private static func errorCase(_ error: Error) -> String {
        String(describing: error).components(separatedBy: "(").first ?? String(describing: error)
    }
}
