import os

public actor LiveSpeakerAssignmentUseCase {
    public private(set) var currentSegments: [DiarizedSpeakerSegment] = []

    private let provider: any StreamingSpeakerDiarizationProvider

    public init(provider: any StreamingSpeakerDiarizationProvider) {
        self.provider = provider
    }

    public func start(preEnrolled: [Voiceprint]) async throws {
        currentSegments = []
        Log.diarization.info(
            "live speaker assignment start preEnrolled=\(preEnrolled.count, privacy: .public) currentSegments=\(self.currentSegments.count, privacy: .public)"
        )

        do {
            try await provider.start(preEnrolled: preEnrolled)
        } catch {
            logFailure(operation: "start", preEnrolledCount: preEnrolled.count)
            throw error
        }
    }

    public func ingest(
        samples: [Float],
        sourceSampleRate: Double
    ) async throws -> [DiarizedSpeakerSegment] {
        do {
            let emittedSegments = try await provider.process(
                samples: samples,
                sourceSampleRate: sourceSampleRate
            )
            append(emittedSegments)
            return currentSegments
        } catch {
            logFailure(
                operation: "ingest",
                sampleCount: samples.count,
                sourceSampleRate: sourceSampleRate
            )
            throw error
        }
    }

    public func finish() async throws -> [DiarizedSpeakerSegment] {
        do {
            let emittedSegments = try await provider.finish()
            append(emittedSegments)
            return currentSegments
        } catch {
            logFailure(operation: "finish")
            throw error
        }
    }

    private func append(_ segments: [DiarizedSpeakerSegment]) {
        guard !segments.isEmpty else {
            return
        }

        currentSegments.append(contentsOf: segments)
        currentSegments = Self.sortedByTimeline(currentSegments)
    }

    private static func sortedByTimeline(
        _ segments: [DiarizedSpeakerSegment]
    ) -> [DiarizedSpeakerSegment] {
        segments.sorted { lhs, rhs in
            if lhs.startSeconds != rhs.startSeconds {
                return lhs.startSeconds < rhs.startSeconds
            }
            if lhs.endSeconds != rhs.endSeconds {
                return lhs.endSeconds < rhs.endSeconds
            }
            return lhs.speakerId < rhs.speakerId
        }
    }

    private func logFailure(
        operation: String,
        preEnrolledCount: Int = 0,
        sampleCount: Int = 0,
        sourceSampleRate: Double = 0
    ) {
        Log.diarization.error(
            "live speaker assignment failed operation=\(operation, privacy: .public) preEnrolled=\(preEnrolledCount, privacy: .public) samples=\(sampleCount, privacy: .public) sourceSampleRate=\(sourceSampleRate, privacy: .public) currentSegments=\(self.currentSegments.count, privacy: .public)"
        )
    }
}
