import Foundation
import Testing
@testable import MintoCore

/// Step 4 실오디오 AB: VBx 타임라인을 고정하고 matcher-only vs matcher+SentenceSpeakerSplitter를
/// 비교해 "문장 단위 분할이 청크에 갇힌 소수 화자를 살리는가"를 측정한다.
/// 저장 회의 transcript(words 포함) + 같은 회의의 아카이브 오디오로 VBx를 재실행한다.
/// 실행:
///   RUN_SPLITTER_EVAL=1 \
///   MEETING_JSON="~/Library/Application Support/Minto/meetings/<id>.json" \
///   DIARIZATION_EVAL_WAV="~/Library/Application Support/Minto/audio/<id>.wav" \
///   [EXPECTED_SPEAKERS=4] \
///   ./scripts/dev.sh test SentenceSplitterEvalTests
@Suite("문장 분할 실오디오 AB", .serialized)
struct SentenceSplitterEvalTests {
    @Test(
        "matcher-only vs matcher+splitter 화자 보존 비교",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_SPLITTER_EVAL"] == "1")
    )
    func measuresSplitterRecovery() async throws {
        let env = ProcessInfo.processInfo.environment
        let jsonPath = try #require(env["MEETING_JSON"]?.trimmingCharacters(in: .whitespacesAndNewlines), "MEETING_JSON 필요")
        let wavPath = try #require(env["DIARIZATION_EVAL_WAV"]?.trimmingCharacters(in: .whitespacesAndNewlines), "DIARIZATION_EVAL_WAV 필요")
        let jsonURL = URL(fileURLWithPath: (jsonPath as NSString).expandingTildeInPath)
        let wavURL = URL(fileURLWithPath: (wavPath as NSString).expandingTildeInPath)
        try #require(FileManager.default.fileExists(atPath: jsonURL.path), "JSON 없음: \(jsonURL.path)")
        try #require(FileManager.default.fileExists(atPath: wavURL.path), "WAV 없음: \(wavURL.path)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(MeetingRecord.self, from: Data(contentsOf: jsonURL))
        let transcript = record.transcript
        try #require(!transcript.isEmpty, "transcript 비어있음")

        let meetingStart = transcript.first?.timestamp ?? record.startedAt
        let wordCoveredSegments = transcript.filter { ($0.words?.isEmpty == false) }.count

        // VBx 1회 실행 → 양쪽에 같은 타임라인을 먹인다(효과 격리).
        let provider: FluidAudioOfflineDiarizationProvider
        if let expected = env["EXPECTED_SPEAKERS"].flatMap(Int.init), expected > 0 {
            provider = FluidAudioOfflineDiarizationProvider(exactSpeakerCount: expected)
        } else {
            provider = FluidAudioOfflineDiarizationProvider()
        }
        let diarization = try await provider.diarizeWithSegmentsAndEmbeddings(audioFileURL: wavURL)
        let diarSegments = diarization.segments
        let vbxSpeakers = Set(diarSegments.map(\.speakerId)).count

        // A: matcher only
        let matched = TranscriptSpeakerMatcher().assignSpeakers(
            diarizedSegments: diarSegments,
            transcript: transcript,
            meetingStart: meetingStart
        )
        let matcherSpeakers = Set(matched.compactMap { SpeakerLabel.normalized($0.speaker) }).count

        // B: matcher + splitter (배선과 동일 순서)
        let split = SentenceSpeakerSplitter().split(
            transcript: matched,
            diarizedSegments: diarSegments,
            meetingStart: meetingStart
        )
        let splitterSpeakers = Set(split.compactMap { SpeakerLabel.normalized($0.speaker) }).count

        // 청크에 갇힌 다수 화자: matcher 세그먼트 중 word들이 2명 이상 VBx 화자에 걸친 수
        let timeline = diarSegments.filter { $0.endSeconds > $0.startSeconds }
        let labelMap = DiarizationSpeakerLabeling.makeLabelMap(from: timeline)
        var collapsedSegments = 0
        for segment in transcript {
            guard let words = segment.words, !words.isEmpty else { continue }
            let segStart = segment.timestamp.timeIntervalSince(meetingStart)
            var labels = Set<String>()
            for word in words {
                let wStart = segStart + word.start
                let wEnd = segStart + word.end
                let best = timeline
                    .filter { max(0, min(wEnd, $0.endSeconds) - max(wStart, $0.startSeconds)) > 0 }
                    .max { lhs, rhs in
                        let lo = min(wEnd, lhs.endSeconds) - max(wStart, lhs.startSeconds)
                        let ro = min(wEnd, rhs.endSeconds) - max(wStart, rhs.startSeconds)
                        return lo < ro
                    }
                if let best, let label = labelMap[best.speakerId] { labels.insert(label) }
            }
            if labels.count > 1 { collapsedSegments += 1 }
        }

        // word 드리프트 sanity: 단조성 위반·세그먼트 밖 word 비율
        var totalWords = 0
        var outOfBounds = 0
        var nonMonotonic = 0
        for segment in transcript {
            guard let words = segment.words, !words.isEmpty else { continue }
            var prevEnd = -Double.infinity
            for word in words {
                totalWords += 1
                if word.start < -0.05 || word.end > segment.duration + 0.5 { outOfBounds += 1 }
                if word.start + 1e-6 < prevEnd { nonMonotonic += 1 }
                prevEnd = word.end
            }
        }

        print("""

        ===== Sentence Splitter AB (\(jsonURL.lastPathComponent)) =====
        transcript segments=\(transcript.count) wordCovered=\(wordCoveredSegments) totalWords=\(totalWords)
        VBx speakers=\(vbxSpeakers) (exactN=\(env["EXPECTED_SPEAKERS"] ?? "auto"))
        [A] matcher-only : segments=\(matched.count) distinctSpeakers=\(matcherSpeakers)
        [B] +splitter    : segments=\(split.count) distinctSpeakers=\(splitterSpeakers)
        recovered: speakers +\(splitterSpeakers - matcherSpeakers), segments +\(split.count - matched.count)
        collapsedSegments(words span >1 VBx speaker)=\(collapsedSegments)
        word drift sanity: outOfBounds=\(outOfBounds)/\(totalWords) nonMonotonic=\(nonMonotonic)/\(totalWords)
        =====================================================

        """)

        #expect(vbxSpeakers > 0)
        #expect(split.count >= matched.count)
        #expect(splitterSpeakers >= matcherSpeakers)
    }
}
