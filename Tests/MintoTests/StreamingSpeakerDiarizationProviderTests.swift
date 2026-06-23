import Foundation
import Testing
@preconcurrency import FluidAudio
@testable import MintoCore

@Suite("StreamingSpeakerDiarizationProvider")
struct StreamingSpeakerDiarizationProviderTests {
    @Test("DiarizerTimelineUpdate의 finalized와 tentative segment를 Minto segment로 변환한다")
    func convertsTimelineUpdateSegments() {
        let update = DiarizerTimelineUpdate(
            finalizedSegments: [
                DiarizerSegment(
                    speakerIndex: 2,
                    startFrame: 2,
                    endFrame: 5,
                    finalized: true,
                    frameDurationSeconds: 0.5
                )
            ],
            tentativeSegments: [
                DiarizerSegment(
                    speakerIndex: 0,
                    startFrame: 5,
                    endFrame: 7,
                    finalized: false,
                    frameDurationSeconds: 0.5
                )
            ],
            chunkResult: DiarizerChunkResult(
                finalizedPredictions: [],
                finalizedFrameCount: 0
            )
        )

        let segments = FluidAudioLSEENDStreamingProvider.toDiarizedSegments(update)

        #expect(segments == [
            DiarizedSpeakerSegment(speakerId: "Speaker 2", startSeconds: 1.0, endSeconds: 2.5),
            DiarizedSpeakerSegment(speakerId: "Speaker 0", startSeconds: 2.5, endSeconds: 3.5),
        ])
    }

    @Test("빈 timeline update는 빈 segment 배열로 변환한다")
    func convertsEmptyTimelineUpdate() {
        let update = DiarizerTimelineUpdate(
            chunkResult: DiarizerChunkResult(
                finalizedPredictions: [],
                finalizedFrameCount: 0
            )
        )

        #expect(FluidAudioLSEENDStreamingProvider.toDiarizedSegments(update).isEmpty)
    }
}

@Suite("FluidAudioLSEENDStreamingProvider 통합", .serialized)
struct FluidAudioLSEENDStreamingProviderIntegrationTests {
    @Test(
        "RUN_LSEEND_POC=1일 때 실제 WAV를 스트리밍 처리한다",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_LSEEND_POC"] == "1")
    )
    func processesWavWhenExplicitlyEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        let wavPath = try #require(
            nonEmptyEnvironmentValue("DIARIZATION_EVAL_WAV", in: environment),
            "DIARIZATION_EVAL_WAV가 필요합니다"
        )
        let wavURL = URL(fileURLWithPath: wavPath)
        try #require(FileManager.default.fileExists(atPath: wavURL.path), "WAV 파일이 존재해야 합니다")

        let variantName = (nonEmptyEnvironmentValue("LSEEND_VARIANT", in: environment) ?? "dihard3")
            .lowercased()
        let samples = try AudioConverter().resampleAudioFile(wavURL)
        try #require(!samples.isEmpty, "AudioConverter가 빈 샘플을 반환했습니다")

        let provider = FluidAudioLSEENDStreamingProvider(
            variant: try lseendVariant(named: variantName)
        )
        try await provider.start(preEnrolled: [])

        let chunkSampleCount = 16_000
        var emittedSegments: [DiarizedSpeakerSegment] = []
        var cursor = samples.startIndex
        while cursor < samples.endIndex {
            let end = min(cursor + chunkSampleCount, samples.endIndex)
            emittedSegments += try await provider.process(
                samples: Array(samples[cursor..<end]),
                sourceSampleRate: 16_000
            )
            cursor = end
        }
        emittedSegments += try await provider.finish()

        #expect(!emittedSegments.isEmpty, "LS-EEND streaming provider 결과 segment가 있어야 합니다")
    }

    private func nonEmptyEnvironmentValue(
        _ key: String,
        in environment: [String: String]
    ) -> String? {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func lseendVariant(named rawValue: String) throws -> LSEENDVariant {
        switch rawValue.lowercased() {
        case "ami":
            return .ami
        case "callhome":
            return .callhome
        case "dihard2":
            return .dihard2
        case "dihard3":
            return .dihard3
        default:
            throw LSEENDStreamingProviderTestError.invalidVariant(value: rawValue)
        }
    }
}

private enum LSEENDStreamingProviderTestError: Error, CustomStringConvertible {
    case invalidVariant(value: String)

    var description: String {
        switch self {
        case .invalidVariant(let value):
            return "LSEEND_VARIANT는 ami, callhome, dihard2, dihard3 중 하나여야 합니다: \(value)"
        }
    }
}
