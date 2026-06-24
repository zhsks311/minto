import Foundation
import Testing
@testable import MintoCore

@Suite("LiveDiarizationFinalizeUseCase")
struct LiveDiarizationFinalizeUseCaseTests {
    private let meetingStart = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("VBx 화자를 시간 겹침으로 transcript에 배정한다")
    func assignsVBxSpeakersByTime() async throws {
        let useCase = makeUseCase(
            segments: [
                diarized("vbx-a", start: 0, end: 4),
                diarized("vbx-b", start: 4, end: 8),
            ],
            embeddings: [
                (speakerId: "vbx-a", embedding: [1, 0]),
                (speakerId: "vbx-b", embedding: [0, 1]),
            ]
        )

        let result = try await useCase.finalize(
            audioFileURL: audioURL(),
            liveTranscript: [
                segment(offset: 0, duration: 4, speaker: "화자 1"),
                segment(offset: 4, duration: 4, speaker: "화자 1"),
            ],
            editedSegmentIds: [],
            enrolledVoiceprints: [],
            meetingStart: meetingStart,
            expectedSpeakerCount: nil
        )

        #expect(result.segments.map(\.speaker) == ["화자 1", "화자 2"])
        #expect(result.speakerEmbeddings.map(\.speakerLabel) == ["화자 1", "화자 2"])
    }

    @Test("최종 화자 수는 라이브 라벨이 아니라 VBx 카운트를 따른다(상한 없음)")
    func finalCountFollowsVBxNotLive() async throws {
        // 라이브에선 전부 "화자 1"(과소추정)이었어도, VBx가 3명을 시간으로 나누면 최종은 3명.
        let useCase = makeUseCase(
            segments: [
                diarized("vbx-a", start: 0, end: 4),
                diarized("vbx-b", start: 4, end: 8),
                diarized("vbx-c", start: 8, end: 12),
            ],
            embeddings: [
                (speakerId: "vbx-a", embedding: [1, 0]),
                (speakerId: "vbx-b", embedding: [0, 1]),
                (speakerId: "vbx-c", embedding: [1, 1]),
            ]
        )

        let result = try await useCase.finalize(
            audioFileURL: audioURL(),
            liveTranscript: [
                segment(offset: 0, duration: 4, speaker: "화자 1"),
                segment(offset: 4, duration: 4, speaker: "화자 1"),
                segment(offset: 8, duration: 4, speaker: "화자 1"),
            ],
            editedSegmentIds: [],
            enrolledVoiceprints: [],
            meetingStart: meetingStart,
            expectedSpeakerCount: nil
        )

        #expect(Set(result.segments.compactMap(\.speaker)) == ["화자 1", "화자 2", "화자 3"])
    }

    @Test("편집된 segment는 VBx 배정으로 덮지 않는다")
    func preservesEditedSegments() async throws {
        let editedID = Segment.ID()
        let useCase = makeUseCase(
            segments: [
                diarized("vbx-a", start: 0, end: 4),
                diarized("vbx-b", start: 4, end: 12),
            ],
            embeddings: [
                (speakerId: "vbx-a", embedding: [1, 0]),
                (speakerId: "vbx-b", embedding: [0, 1]),
            ]
        )

        let result = try await useCase.finalize(
            audioFileURL: audioURL(),
            liveTranscript: [
                segment(offset: 0, duration: 4, speaker: "화자 1"),
                segment(id: editedID, offset: 4, duration: 4, speaker: "박팀장"),
                segment(offset: 8, duration: 4, speaker: "화자 1"),
            ],
            editedSegmentIds: [editedID],
            enrolledVoiceprints: [],
            meetingStart: meetingStart,
            expectedSpeakerCount: nil
        )

        #expect(result.segments.map(\.speaker) == ["화자 1", "박팀장", "화자 2"])
        #expect(result.segments[1].id == editedID)
    }

    @Test("보이스프린트 매칭 시 transcript와 embedding 라벨을 실명으로 치환한다")
    func identifiesMatchedVoiceprint() async throws {
        let useCase = makeUseCase(
            segments: [
                diarized("vbx-a", start: 0, end: 4),
                diarized("vbx-b", start: 4, end: 8),
            ],
            embeddings: [
                (speakerId: "vbx-a", embedding: [2, 0]),
                (speakerId: "vbx-b", embedding: [0, 1]),
            ]
        )

        let result = try await useCase.finalize(
            audioFileURL: audioURL(),
            liveTranscript: [
                segment(offset: 0, duration: 4, speaker: "화자 1"),
                segment(offset: 4, duration: 4, speaker: "화자 1"),
            ],
            editedSegmentIds: [],
            enrolledVoiceprints: [
                voiceprint(name: "Alice", embedding: [1, 0])
            ],
            meetingStart: meetingStart,
            expectedSpeakerCount: nil
        )

        #expect(result.segments.map(\.speaker) == ["Alice", "화자 2"])
        #expect(result.speakerEmbeddings.map(\.speakerLabel) == ["Alice", "화자 2"])
    }

    @Test("등록 보이스프린트가 없으면 VBx 자동 라벨을 유지한다")
    func keepsGeneratedLabelsWhenNoVoiceprintsAreEnrolled() async throws {
        let useCase = makeUseCase(
            segments: [diarized("vbx-a", start: 0, end: 4)],
            embeddings: [(speakerId: "vbx-a", embedding: [1, 0])]
        )

        let result = try await useCase.finalize(
            audioFileURL: audioURL(),
            liveTranscript: [segment(offset: 0, duration: 4, speaker: "화자 1")],
            editedSegmentIds: [],
            enrolledVoiceprints: [],
            meetingStart: meetingStart,
            expectedSpeakerCount: nil
        )

        #expect(result.segments.map(\.speaker) == ["화자 1"])
        #expect(result.speakerEmbeddings.map(\.speakerLabel) == ["화자 1"])
    }

    @Test("미편집 transcript 라벨과 speakerEmbeddings 키를 일치시킨다")
    func keepsTranscriptAndEmbeddingSpeakerKeysAligned() async throws {
        let useCase = makeUseCase(
            segments: [
                diarized("vbx-a", start: 0, end: 4),
                diarized("vbx-b", start: 4, end: 8),
            ],
            embeddings: [
                (speakerId: "vbx-a", embedding: [1, 0]),
                (speakerId: "vbx-b", embedding: [0, 1]),
            ]
        )

        let result = try await useCase.finalize(
            audioFileURL: audioURL(),
            liveTranscript: [
                segment(offset: 0, duration: 4, speaker: "화자 1"),
                segment(offset: 4, duration: 4, speaker: "화자 1"),
            ],
            editedSegmentIds: [],
            enrolledVoiceprints: [
                voiceprint(name: "Alice", embedding: [1, 0]),
                voiceprint(name: "Bob", embedding: [0, 1]),
            ],
            meetingStart: meetingStart,
            expectedSpeakerCount: nil
        )

        let transcriptLabels = Set(result.segments.compactMap(\.speaker))
        let embeddingLabels = Set(result.speakerEmbeddings.map(\.speakerLabel))
        #expect(transcriptLabels == embeddingLabels)
    }

    private func makeUseCase(
        segments: [DiarizedSpeakerSegment],
        embeddings: [(speakerId: String, embedding: [Float])]
    ) -> LiveDiarizationFinalizeUseCase {
        LiveDiarizationFinalizeUseCase(
            diarizer: MockSegmentEmbeddingDiarizer(
                segments: segments,
                embeddings: embeddings
            )
        )
    }

    private func segment(
        id: Segment.ID = Segment.ID(),
        offset: TimeInterval,
        duration: TimeInterval,
        speaker: String?
    ) -> Segment {
        Segment(
            id: id,
            text: "전사 \(offset)",
            timestamp: meetingStart.addingTimeInterval(offset),
            duration: duration,
            speaker: speaker,
            words: nil
        )
    }

    private func diarized(_ speakerId: String, start: Double, end: Double) -> DiarizedSpeakerSegment {
        DiarizedSpeakerSegment(speakerId: speakerId, startSeconds: start, endSeconds: end)
    }

    private func voiceprint(name: String, embedding: [Float]) -> Voiceprint {
        Voiceprint(
            displayName: name,
            embedding: embedding,
            embeddingModelID: FluidAudioOfflineDiarizationProvider.embeddingModelID,
            enrolledAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func audioURL() -> URL {
        URL(fileURLWithPath: "/tmp/minto-live-finalize-test.wav")
    }
}

private struct MockSegmentEmbeddingDiarizer: SegmentEmbeddingDiarizing {
    let segments: [DiarizedSpeakerSegment]
    let embeddings: [(speakerId: String, embedding: [Float])]

    func diarizeWithSegmentsAndEmbeddings(
        audioFileURL: URL
    ) async throws -> (
        segments: [DiarizedSpeakerSegment],
        embeddings: [(speakerId: String, embedding: [Float])]
    ) {
        (segments: segments, embeddings: embeddings)
    }
}
