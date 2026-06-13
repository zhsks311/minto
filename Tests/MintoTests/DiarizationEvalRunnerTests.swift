import Foundation
import Testing
@testable import MintoCore

@Suite("Diarization 평가 러너", .serialized)
struct DiarizationEvalRunnerTests {
    @Test(
        "FluidAudio offline diarization을 실제 WAV에 대해 실행한다",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_DIARIZATION_EVAL"] == "1")
    )
    func runsFluidAudioOfflineDiarization() async throws {
        let environment = ProcessInfo.processInfo.environment
        let wavPath = try #require(
            nonEmptyEnvironmentValue("DIARIZATION_EVAL_WAV", in: environment),
            "DIARIZATION_EVAL_WAV가 필요합니다"
        )
        let wavURL = URL(fileURLWithPath: wavPath)
        try #require(FileManager.default.fileExists(atPath: wavURL.path), "WAV 파일이 존재해야 합니다")

        let warmStartFa = try doubleEnvironmentValue("DIARIZATION_WARMSTART_FA", in: environment)
        let clusteringThreshold = try doubleEnvironmentValue("DIARIZATION_CLUSTERING_THRESHOLD", in: environment)
        let provider = FluidAudioOfflineDiarizationProvider(
            clusteringThreshold: clusteringThreshold,
            warmStartFa: warmStartFa
        )

        let diarizedSegments = try await provider.diarize(audioFileURL: wavURL)
        let speakerCount = Set(diarizedSegments.map(\.speakerId)).count
        Log.diarization.info(
            "diarization eval result segments=\(diarizedSegments.count, privacy: .public) speakers=\(speakerCount, privacy: .public)"
        )
        // 평가 러너는 측정값을 눈으로 봐야 하므로 stdout에도 찍는다(Log는 통합 로깅이라 캡처가 안 됨).
        // print 금지 규칙은 제품 Sources 대상이고, 이 게이트 테스트는 측정 출력이 목적이다.
        print("[DIAR-EVAL] fa=\(warmStartFa.map { "\($0)" } ?? "default") threshold=\(clusteringThreshold.map { "\($0)" } ?? "default") diarizedSegments=\(diarizedSegments.count) uniqueSpeakers=\(speakerCount)")
        #expect(!diarizedSegments.isEmpty, "FluidAudio diarization 결과 segment가 있어야 합니다")

        guard let transcriptPath = nonEmptyEnvironmentValue(
            "DIARIZATION_EVAL_TRANSCRIPT_JSON",
            in: environment
        ) else {
            return
        }

        let transcriptURL = URL(fileURLWithPath: transcriptPath)
        try #require(FileManager.default.fileExists(atPath: transcriptURL.path), "전사 JSON 파일이 존재해야 합니다")
        let data = try Data(contentsOf: transcriptURL)
        let record = try MeetingRecordCoding.makeDecoder().decode(MeetingRecord.self, from: data)

        let matcher = TranscriptSpeakerMatcher()
        let matchedTranscript = matcher.assignSpeakers(
            diarizedSegments: diarizedSegments,
            transcript: record.transcript,
            meetingStart: record.startedAt
        )
        let metrics = DiarizationQualityMetrics.calculate(
            diarizedSegments: diarizedSegments,
            matchedTranscript: matchedTranscript,
            meetingStart: record.startedAt
        )

        Log.diarization.info(
            "diarization eval metrics transcriptSegments=\(metrics.transcriptSegmentCount, privacy: .public) labeledSegments=\(metrics.labeledTranscriptSegmentCount, privacy: .public) switches=\(metrics.speakerSwitchCount, privacy: .public) coverage=\(metrics.transcriptCoverage, privacy: .public) timeCoverage=\(metrics.transcriptTimeCoverage, privacy: .public) averageOverlap=\(metrics.averageOverlapRatio, privacy: .public)"
        )
        print(String(
            format: "[DIAR-EVAL] uniqueSpeakers=%d transcriptSegments=%d labeled=%d switches=%d coverage=%.3f timeCoverage=%.3f avgOverlap=%.3f",
            metrics.uniqueSpeakerCount, metrics.transcriptSegmentCount, metrics.labeledTranscriptSegmentCount,
            metrics.speakerSwitchCount, metrics.transcriptCoverage, metrics.transcriptTimeCoverage, metrics.averageOverlapRatio
        ))
        #expect(metrics.transcriptSegmentCount == record.transcript.count)
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

    private func doubleEnvironmentValue(
        _ key: String,
        in environment: [String: String]
    ) throws -> Double? {
        guard let rawValue = nonEmptyEnvironmentValue(key, in: environment) else { return nil }
        guard let value = Double(rawValue) else {
            throw DiarizationEvalRunnerError.invalidDouble(key: key, value: rawValue)
        }
        return value
    }
}

private enum DiarizationEvalRunnerError: Error, CustomStringConvertible {
    case invalidDouble(key: String, value: String)

    var description: String {
        switch self {
        case .invalidDouble(let key, let value):
            return "\(key)는 Double 값이어야 합니다: \(value)"
        }
    }
}
