import Foundation
import Testing
@testable import MintoCore

@Suite("LiveDiarizationFinalizeUseCase")
struct LiveDiarizationFinalizeUseCaseTests {
    private let meetingStart = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("라이브 라벨을 VBx 라벨로 재조정해 transcript에 반영한다")
    func mapsLiveLabelsToFinalVBxLabels() async throws {
        // transcript.speaker는 Phase 3가 makeLabelMap으로 부여한 "화자 N" 공간이다
        // (liveSpeakerSegments live-a→화자 1, live-b→화자 2).
        let liveTranscript = [
            segment(offset: 0, duration: 4, speaker: "화자 1"),
            segment(offset: 4, duration: 4, speaker: "화자 2"),
        ]
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
            liveTranscript: liveTranscript,
            liveSpeakerSegments: [
                diarized("live-a", start: 0, end: 4),
                diarized("live-b", start: 4, end: 8),
            ],
            editedSegmentIds: [],
            enrolledVoiceprints: [],
            meetingStart: meetingStart,
            expectedSpeakerCount: nil
        )

        #expect(result.segments.map(\.speaker) == ["화자 1", "화자 2"])
        #expect(result.speakerEmbeddings.map(\.speakerLabel) == ["화자 1", "화자 2"])
    }

    @Test("편집된 segment는 재조정과 실명 치환을 모두 건너뛴다")
    func preservesEditedSegmentsDuringRelabelingAndIdentification() async throws {
        let editedLiveID = Segment.ID()
        let editedFinalID = Segment.ID()
        let liveTranscript = [
            segment(offset: 0, duration: 4, speaker: "화자 1"),
            segment(id: editedLiveID, offset: 4, duration: 4, speaker: "live-b"),
            segment(id: editedFinalID, offset: 8, duration: 4, speaker: "화자 2"),
        ]
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
            liveTranscript: liveTranscript,
            liveSpeakerSegments: [
                diarized("live-a", start: 0, end: 4),
                diarized("live-b", start: 4, end: 12),
            ],
            editedSegmentIds: [editedLiveID, editedFinalID],
            enrolledVoiceprints: [
                voiceprint(name: "Bob", embedding: [0, 1])
            ],
            meetingStart: meetingStart,
            expectedSpeakerCount: 2
        )

        #expect(result.segments.map(\.speaker) == ["화자 1", "live-b", "화자 2"])
        #expect(result.segments[1].id == editedLiveID)
        #expect(result.segments[2].id == editedFinalID)
        // Bob은 화자 2와 매칭되지만 화자 2 segment가 전부 편집 보존돼 transcript가 안 바뀌므로,
        // embedding 라벨도 실명으로 치환하지 않는다(transcript↔embedding 키 일관성 유지).
        #expect(result.speakerEmbeddings.map(\.speakerLabel) == ["화자 1", "화자 2"])
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
                segment(offset: 4, duration: 4, speaker: "화자 2"),
            ],
            liveSpeakerSegments: [
                diarized("live-a", start: 0, end: 4),
                diarized("live-b", start: 4, end: 8),
            ],
            editedSegmentIds: [],
            enrolledVoiceprints: [
                voiceprint(name: "Alice", embedding: [1, 0])
            ],
            meetingStart: meetingStart,
            expectedSpeakerCount: 2
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
            liveSpeakerSegments: [diarized("live-a", start: 0, end: 4)],
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
                segment(offset: 4, duration: 4, speaker: "화자 2"),
            ],
            liveSpeakerSegments: [
                diarized("live-a", start: 0, end: 4),
                diarized("live-b", start: 4, end: 8),
            ],
            editedSegmentIds: [],
            enrolledVoiceprints: [
                voiceprint(name: "Alice", embedding: [1, 0]),
                voiceprint(name: "Bob", embedding: [0, 1]),
            ],
            meetingStart: meetingStart,
            expectedSpeakerCount: 2
        )

        let transcriptLabels = Set(result.segments.compactMap(\.speaker))
        let embeddingLabels = Set(result.speakerEmbeddings.map(\.speakerLabel))
        #expect(transcriptLabels == embeddingLabels)
    }

    @Test("라이브 화자 세그먼트가 비면 재조정 없이 라이브 라벨을 유지한다")
    func keepsLiveLabelsWhenNoLiveSpeakerSegments() async throws {
        let useCase = makeUseCase(
            segments: [diarized("vbx-a", start: 0, end: 4)],
            embeddings: [(speakerId: "vbx-a", embedding: [1, 0])]
        )

        let result = try await useCase.finalize(
            audioFileURL: audioURL(),
            liveTranscript: [segment(offset: 0, duration: 4, speaker: "화자 1")],
            liveSpeakerSegments: [],
            editedSegmentIds: [],
            enrolledVoiceprints: [],
            meetingStart: meetingStart,
            expectedSpeakerCount: nil
        )

        #expect(result.segments.map(\.speaker) == ["화자 1"])
    }

    @Test("라이브 화자 수가 VBx보다 많으면 미매칭 라이브 라벨을 유지한다")
    func keepsUnmatchedLiveLabelWhenLiveHasMoreSpeakers() async throws {
        let useCase = makeUseCase(
            segments: [diarized("vbx-a", start: 0, end: 4)],
            embeddings: [(speakerId: "vbx-a", embedding: [1, 0])]
        )

        let result = try await useCase.finalize(
            audioFileURL: audioURL(),
            liveTranscript: [
                segment(offset: 0, duration: 4, speaker: "화자 1"),
                segment(offset: 5, duration: 4, speaker: "화자 2"),
            ],
            liveSpeakerSegments: [
                diarized("live-a", start: 0, end: 4),
                diarized("live-b", start: 5, end: 9),
            ],
            editedSegmentIds: [],
            enrolledVoiceprints: [],
            meetingStart: meetingStart,
            expectedSpeakerCount: nil
        )

        // 화자 1은 VBx 화자 1과 매칭, 화자 2는 VBx에 대응이 없어 라이브 라벨을 유지(fallback).
        #expect(result.segments.map(\.speaker) == ["화자 1", "화자 2"])
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
