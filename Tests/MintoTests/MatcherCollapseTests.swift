import Foundation
import Testing
@testable import MintoCore

/// 가설 검증: VBx가 화자 N명을 찾아도, TranscriptSpeakerMatcher가 긴(33~60s) transcript 문단에
/// 화자 하나씩만 배정해 화면 화자 수가 붕괴하는가? 실제 저장 회의 transcript + 같은 오디오의 VBx diar로 측정.
/// 실행: RUN_MATCHER_TEST=1 DIARIZATION_EVAL_WAV=<wav> MEETING_JSON=<meeting.json> ./scripts/dev.sh test MatcherCollapseTests
@Suite("매처 붕괴 측정", .serialized)
struct MatcherCollapseTests {
    @Test(
        "VBx diar 화자 수 vs 매처 적용 후 transcript 화자 수",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_MATCHER_TEST"] == "1")
    )
    func measuresMatcherCollapse() async throws {
        let env = ProcessInfo.processInfo.environment
        let wavPath = try #require(env["DIARIZATION_EVAL_WAV"]?.trimmingCharacters(in: .whitespacesAndNewlines), "DIARIZATION_EVAL_WAV 필요")
        let jsonPath = try #require(env["MEETING_JSON"]?.trimmingCharacters(in: .whitespacesAndNewlines), "MEETING_JSON 필요")
        let wavURL = URL(fileURLWithPath: wavPath)
        let jsonURL = URL(fileURLWithPath: jsonPath)
        try #require(FileManager.default.fileExists(atPath: wavURL.path), "WAV 없음")
        try #require(FileManager.default.fileExists(atPath: jsonURL.path), "JSON 없음")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(MeetingRecord.self, from: Data(contentsOf: jsonURL))
        let transcript = record.transcript
        try #require(!transcript.isEmpty, "transcript 비어있음")

        let provider = FluidAudioOfflineDiarizationProvider()
        let diarization = try await provider.diarizeWithSegmentsAndEmbeddings(audioFileURL: wavURL)
        let diarSegments = diarization.segments
        let vbxSpeakers = Set(diarSegments.map(\.speakerId)).count

        let meetingStart = transcript.first?.timestamp ?? record.startedAt
        let matched = TranscriptSpeakerMatcher().assignSpeakers(
            diarizedSegments: diarSegments,
            transcript: transcript,
            meetingStart: meetingStart
        )
        let transcriptSpeakers = Set(matched.compactMap { SpeakerLabel.normalized($0.speaker) }).count

        let durations = transcript.map(\.duration)
        let avgDur = durations.reduce(0, +) / Double(max(1, durations.count))
        let maxDur = durations.max() ?? 0

        print(String(
            format: "[MATCHER] vbxRawSpeakers=%d transcriptSpeakersAfterMatch=%d transcriptSegments=%d avgSegDur=%.1f maxSegDur=%.1f",
            vbxSpeakers, transcriptSpeakers, transcript.count, avgDur, maxDur
        ))
        #expect(vbxSpeakers > 0)
    }
}
