import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("TranscriptEditing", .serialized)
struct TranscriptEditingTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("minto-transcript-edit-\(UUID().uuidString)", isDirectory: true)
    }

    private func record(
        id: UUID = UUID(),
        summary: MeetingSummary = MeetingSummary(leadAnswer: "요약"),
        transcript: [Segment]
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: "편집 회의",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 120,
            topic: "원래 주제",
            summary: summary,
            transcript: transcript,
            audioFileName: "meeting.wav",
            speakerEmbeddings: [
                .init(speakerLabel: "화자 1", embedding: [1, 0], embeddingModelID: "speaker-v1")
            ]
        )
    }

    private func segment(
        id: UUID = UUID(),
        text: String,
        seconds: TimeInterval = 0,
        duration: TimeInterval = 5,
        speaker: String? = "화자 1",
        words: [WordTimestamp]? = nil
    ) -> Segment {
        Segment(
            id: id,
            text: text,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000 + seconds),
            duration: duration,
            speaker: speaker,
            words: words
        )
    }

    @Test("텍스트가 바뀐 segment만 교체하고 words를 비운다")
    func editedSegmentPreservesIdentityAndClearsWordsOnlyWhenTextChanges() {
        let changedWords = [WordTimestamp(word: "원본", start: 0, end: 0.5)]
        let unchangedWords = [WordTimestamp(word: "유지", start: 5, end: 5.4)]
        let changedID = UUID()
        let unchangedID = UUID()
        let original = [
            segment(id: changedID, text: "원본 전사", seconds: 0, duration: 3, speaker: "화자 1", words: changedWords),
            segment(id: unchangedID, text: "유지 전사", seconds: 5, duration: 4, speaker: "화자 2", words: unchangedWords)
        ]
        let edited = TranscriptEditDraft.editedSegments(
            from: original,
            draftTexts: [
                changedID: "수정 전사",
                unchangedID: "유지 전사"
            ]
        )

        #expect(edited.count == 2)
        #expect(edited[0].id == changedID)
        #expect(edited[0].timestamp == original[0].timestamp)
        #expect(edited[0].duration == original[0].duration)
        #expect(edited[0].speaker == original[0].speaker)
        #expect(edited[0].text == "수정 전사")
        #expect(edited[0].words == nil)

        #expect(edited[1].id == unchangedID)
        #expect(edited[1].timestamp == original[1].timestamp)
        #expect(edited[1].duration == original[1].duration)
        #expect(edited[1].speaker == original[1].speaker)
        #expect(edited[1].text == "유지 전사")
        #expect(edited[1].words == unchangedWords)
    }

    @Test("공백뿐인 edited segment는 저장 배열에서 제거한다")
    func whitespaceOnlyEditedSegmentIsRemoved() {
        let first = segment(text: "삭제 대상")
        let second = segment(text: "유지 대상", seconds: 6)
        var draft = TranscriptEditDraft(record: record(transcript: [first, second]))

        draft.setText(" \n\t ", for: first.id)

        #expect(draft.editedSegments.map(\.id) == [second.id])
        #expect(draft.editedSegments.map(\.text) == ["유지 대상"])
    }

    @Test("저장은 최신 record에 transcript만 병합하고 다른 필드는 보존한다")
    func saveMergesTranscriptIntoLatestRecord() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let originalSegment = segment(text: "원본 전사")
        let original = record(summary: MeetingSummary(leadAnswer: "초기 요약"), transcript: [originalSegment])
        #expect(store.save(original) == .success)

        var draft = TranscriptEditDraft(record: original)
        draft.setText("수정 전사", for: originalSegment.id)

        var latest = try #require(store.meetings.first)
        latest.summary = MeetingSummary(leadAnswer: "편집 시작 후 만든 요약")
        latest.topic = "편집 중 바뀐 주제"
        #expect(store.save(latest) == .success)

        #expect(TranscriptEditing.save(draft, in: store) == .success)

        let saved = try #require(store.meetings.first)
        #expect(saved.id == original.id)
        #expect(saved.summary.leadAnswer == "편집 시작 후 만든 요약")
        #expect(saved.topic == "편집 중 바뀐 주제")
        #expect(saved.audioFileName == "meeting.wav")
        #expect(saved.speakerEmbeddings == original.speakerEmbeddings)
        #expect(saved.transcript.map(\.text) == ["수정 전사"])
    }

    @Test("저장 후 검색 인덱스와 export는 편집된 전사를 반영한다")
    func saveUpdatesSearchIndexAndExport() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let originalSegment = segment(text: "원본 키워드")
        let original = record(transcript: [originalSegment])
        #expect(store.save(original) == .success)

        var draft = TranscriptEditDraft(record: original)
        draft.setText("편집키워드 반영", for: originalSegment.id)

        #expect(TranscriptEditing.save(draft, in: store) == .success)

        let index = try #require(MeetingSearchIndexStore(directory: dir).load())
        let results = index.search("편집키워드", limit: 5)
        #expect(results.contains { $0.meetingID == original.id })

        let saved = try #require(store.meetings.first)
        let markdown = MeetingExporter.markdown(for: MeetingResult.from(saved))
        #expect(markdown.contains("편집키워드 반영"))
        #expect(!markdown.contains("원본 키워드"))
    }

    @Test("저장 실패는 draft를 지우지 않고 저장 record도 덮지 않는다")
    func failedSaveKeepsDraft() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let originalSegment = segment(text: "원본 전사")
        let original = record(transcript: [originalSegment])
        #expect(store.save(original) == .success)

        var draft = TranscriptEditDraft(record: original)
        draft.setText("실패 후에도 남을 전사", for: originalSegment.id)

        try FileManager.default.removeItem(at: dir)
        try Data("not a directory".utf8).write(to: dir)

        #expect(TranscriptEditing.save(draft, in: store) == .failed)
        #expect(draft.text(for: originalSegment) == "실패 후에도 남을 전사")
        #expect(store.meetings.first?.transcript.first?.text == "원본 전사")
    }

    @Test("전사를 모두 지우고 요약도 없으면 skippedEmpty를 반환한다")
    func emptyTranscriptWithoutSummaryIsSkipped() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let originalSegment = segment(text: "삭제할 전사")
        let original = record(summary: MeetingSummary(), transcript: [originalSegment])
        #expect(store.save(original) == .success)

        var draft = TranscriptEditDraft(record: original)
        draft.setText(" \n ", for: originalSegment.id)

        #expect(TranscriptEditing.save(draft, in: store) == .skippedEmpty)
        #expect(draft.editedSegments.isEmpty)
        #expect(store.meetings.first?.transcript.first?.text == "삭제할 전사")
    }

    @Test("전사를 모두 지워도 요약이 있으면 저장된다")
    func emptyTranscriptWithSummaryIsSaved() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MeetingStore(directory: dir)
        let originalSegment = segment(text: "삭제할 전사")
        let original = record(summary: MeetingSummary(leadAnswer: "남아있는 요약"), transcript: [originalSegment])
        #expect(store.save(original) == .success)

        var draft = TranscriptEditDraft(record: original)
        draft.setText(" \n ", for: originalSegment.id)

        #expect(TranscriptEditing.save(draft, in: store) == .success)
        let saved = try! #require(store.meetings.first)
        #expect(saved.transcript.isEmpty)
        #expect(saved.summary.leadAnswer == "남아있는 요약")
    }
}
