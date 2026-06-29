import Foundation
import Testing
@testable import MintoCore

/// Step 4(c) e2e: 실제 MeetingFileImportUseCase 파이프라인(전사=WhisperKit→매처→SentenceSpeakerSplitter)을
/// 짧은 다화자 클립에 끝까지 돌려, 저장될 transcript가 문장 단위 화자 세그먼트로 나오는지 확인한다.
/// 교정/요약/저장은 스텁(네트워크·부수효과 차단), STT·diarization만 실제.
/// 실행:
///   RUN_SPLITTER_E2E=1 SPLITTER_E2E_WAV="/tmp/splitter-eval/clip5.wav" [EXPECTED_SPEAKERS=5] \
///   ./scripts/dev.sh test SentenceSplitterE2EImportTests
@Suite("문장 분할 e2e 임포트", .serialized)
struct SentenceSplitterE2EImportTests {
    @MainActor
    @Test(
        "실제 import 파이프라인이 문장 단위 화자 세그먼트를 산출한다",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_SPLITTER_E2E"] == "1")
    )
    func importProducesSentenceLevelSegments() async throws {
        let env = ProcessInfo.processInfo.environment
        let wavPath = try #require(env["SPLITTER_E2E_WAV"]?.trimmingCharacters(in: .whitespacesAndNewlines), "SPLITTER_E2E_WAV 필요")
        let wavURL = URL(fileURLWithPath: (wavPath as NSString).expandingTildeInPath)
        try #require(FileManager.default.fileExists(atPath: wavURL.path), "WAV 없음: \(wavURL.path)")
        let expectedSpeakers = env["EXPECTED_SPEAKERS"].flatMap(Int.init)

        let store = CapturingStore()
        let useCase = MeetingFileImportUseCase(
            correctionService: NoopCorrection(),
            summaryService: NoopSummary(),
            store: store
        )

        let record = try await useCase.importFile(
            wavURL,
            expectedSpeakerCount: expectedSpeakers,
            diarizeSpeakers: true,
            engineID: .whisperBalanced,
            shouldCorrect: false
        )

        let transcript = record.transcript
        try #require(!transcript.isEmpty, "transcript 비어있음")

        let speakers = transcript.compactMap { SpeakerLabel.normalized($0.speaker) }
        let distinctSpeakers = Set(speakers).count
        let wordCovered = transcript.filter { ($0.words?.isEmpty == false) }.count
        let totalWords = transcript.reduce(0) { $0 + ($1.words?.count ?? 0) }
        let avgWordsPerSeg = Double(totalWords) / Double(max(1, transcript.count))

        // 화자 전환 지점 수: 인접 세그먼트의 화자가 다른 경계 개수
        var turnChanges = 0
        for index in 1..<max(1, transcript.count) where transcript[index].speaker != transcript[index - 1].speaker {
            turnChanges += 1
        }

        print("""

        ===== Sentence Splitter E2E import (\(wavURL.lastPathComponent)) =====
        segments=\(transcript.count) distinctSpeakers=\(distinctSpeakers) (expected=\(expectedSpeakers.map(String.init) ?? "auto"))
        wordCovered=\(wordCovered)/\(transcript.count) totalWords=\(totalWords) avgWords/seg=\(String(format: "%.1f", avgWordsPerSeg))
        speakerTurnChanges=\(turnChanges)
        --- 처음 12개 세그먼트 ---
        """)
        for segment in transcript.prefix(12) {
            let label = SpeakerLabel.normalized(segment.speaker) ?? "(미배정)"
            let preview = String(segment.text.prefix(28)).replacingOccurrences(of: "\n", with: " ")
            print(String(format: "  [%@] %4.1fs  %@", label, segment.duration, preview))
        }
        print("=====================================================\n")

        #expect(store.savedRecords.count == 1)
        #expect(wordCovered > 0)
        #expect(transcript.count > 0)
    }

    private final class CapturingStore: MeetingFileImportStoring, @unchecked Sendable {
        var savedRecords: [MeetingRecord] = []
        func save(_ record: MeetingRecord) -> MeetingSaveResult {
            savedRecords.append(record)
            return .success
        }
    }

    private final class NoopCorrection: MeetingFileImportCorrecting, @unchecked Sendable {
        func correct(text: String, context: LLMCorrectionContext) async -> String? { nil }
        func correctBatch(texts: [String], context: LLMCorrectionContext) async -> [String?]? { nil }
    }

    private final class NoopSummary: MeetingFileImportSummaryGenerating, @unchecked Sendable {
        func generateFinal(transcript: String, context: SummaryGenerationContext) async -> MeetingSummary? { nil }
        func generateDocumentSummary(document: String) async -> String? { nil }
    }
}
