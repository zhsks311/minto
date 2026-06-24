import Foundation
import Testing
@preconcurrency import FluidAudio
@testable import MintoCore

/// 라이브 스트리밍 경로(FluidAudioLSEENDStreamingProvider: process 청크 + finish)가
/// 실제 WAV에서 검출하는 화자 수를 측정한다. processComplete(배치, LSEENDCountFeasibilityTests)와
/// 비교해 "온라인 스트리밍이 과소추정하는가 / 청크 크기가 레버인가"를 데이터로 확인하는 게이트 테스트.
/// 실행: RUN_LSEEND_STREAM=1 DIARIZATION_EVAL_WAV=<wav> [LSEEND_STREAM_CHUNK_SEC=0.5] ./scripts/dev.sh test LSEENDStreamingCountTests
@Suite("LS-EEND 스트리밍 화자 수 측정", .serialized)
struct LSEENDStreamingCountTests {
    @Test(
        "라이브 스트리밍 경로가 WAV에서 검출한 화자 수를 출력한다",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_LSEEND_STREAM"] == "1")
    )
    func countsStreamingSpeakers() async throws {
        let environment = ProcessInfo.processInfo.environment
        let wavPath = try #require(
            environment["DIARIZATION_EVAL_WAV"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            "DIARIZATION_EVAL_WAV가 필요합니다"
        )
        let wavURL = URL(fileURLWithPath: wavPath)
        try #require(FileManager.default.fileExists(atPath: wavURL.path), "WAV 파일이 존재해야 합니다")

        let chunkSeconds = Double(environment["LSEEND_STREAM_CHUNK_SEC"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0.5
        let sampleRate = 16_000.0
        let chunkSize = max(1, Int(chunkSeconds * sampleRate))

        let samples = try AudioConverter().resampleAudioFile(wavURL)
        try #require(!samples.isEmpty, "빈 샘플")

        let provider = FluidAudioLSEENDStreamingProvider()
        try await provider.start(preEnrolled: [])

        var lastSegments: [DiarizedSpeakerSegment] = []
        var runningSpeakerIDs = Set<String>()
        var index = 0
        while index < samples.count {
            let end = min(index + chunkSize, samples.count)
            let chunk = Array(samples[index..<end])
            let produced = try await provider.process(samples: chunk, sourceSampleRate: sampleRate)
            if !produced.isEmpty {
                lastSegments = produced
                for segment in produced {
                    runningSpeakerIDs.insert(segment.speakerId)
                }
            }
            index = end
        }
        let finalSegments = try await provider.finish()
        for segment in finalSegments {
            runningSpeakerIDs.insert(segment.speakerId)
        }
        let finalSnapshot = finalSegments.isEmpty ? lastSegments : finalSegments
        let finalSpeakerCount = Set(finalSnapshot.map(\.speakerId)).count

        let audioSeconds = Double(samples.count) / sampleRate
        print(String(
            format: "[LSEEND-STREAM] chunkSec=%.2f finalSpeakers=%d runningSpeakers=%d finalSegments=%d audioSec=%.1f",
            chunkSeconds, finalSpeakerCount, runningSpeakerIDs.count, finalSnapshot.count, audioSeconds
        ))
        #expect(!finalSnapshot.isEmpty, "스트리밍 결과 segment가 있어야 합니다")
    }
}
