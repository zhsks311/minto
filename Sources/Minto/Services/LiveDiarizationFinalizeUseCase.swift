import Foundation

public struct LiveDiarizationFinalizeUseCase: Sendable {
    private let diarizer: any SegmentEmbeddingDiarizing

    public init(diarizer: any SegmentEmbeddingDiarizing) {
        self.diarizer = diarizer
    }

    public func finalize(
        audioFileURL: URL,
        liveTranscript: [Segment],
        liveSpeakerSegments: [DiarizedSpeakerSegment],
        editedSegmentIds: Set<Segment.ID>,
        enrolledVoiceprints: [Voiceprint],
        meetingStart: Date,
        // 화자 수 제약은 호출측이 diarizer 생성 시 FluidAudioOfflineDiarizationProvider(exactSpeakerCount:)로
        // 이미 반영한다. 이 파라미터는 관측 로그 전용(여기서 diarize 호출에 다시 쓰지 않는다).
        expectedSpeakerCount: Int?
    ) async throws -> (
        segments: [Segment],
        speakerEmbeddings: [MeetingRecord.MeetingSpeakerEmbedding]
    ) {
        Log.diarization.info(
            "live diarization finalize start transcriptSegments=\(liveTranscript.count, privacy: .public) liveSpeakerSegments=\(liveSpeakerSegments.count, privacy: .public) editedSegments=\(editedSegmentIds.count, privacy: .public) enrolledVoiceprints=\(enrolledVoiceprints.count, privacy: .public) expectedSpeakers=\(expectedSpeakerCount ?? 0, privacy: .public)"
        )

        do {
            let diarization = try await diarizer.diarizeWithSegmentsAndEmbeddings(audioFileURL: audioFileURL)
            let vbxTimeline = diarization.segments.filter { $0.endSeconds > $0.startSeconds }
            let vbxLabelMap = DiarizationSpeakerLabeling.makeLabelMap(from: vbxTimeline)
            let finalLabeled = vbxTimeline.compactMap { segment -> DiarizedSpeakerSegment? in
                guard let label = vbxLabelMap[segment.speakerId] else {
                    return nil
                }
                return DiarizedSpeakerSegment(
                    speakerId: label,
                    startSeconds: segment.startSeconds,
                    endSeconds: segment.endSeconds
                )
            }

            // mapLabels의 live/final은 둘 다 transcript.speaker와 같은 "화자 N" 라벨 공간이어야 한다.
            // liveTranscript.speaker는 Phase 3의 TranscriptSpeakerMatcher(내부 makeLabelMap)로 부여되므로,
            // 여기서 liveSpeakerSegments도 같은 makeLabelMap으로 정규화해 라벨 공간을 맞춘다.
            // (정규화 없이 LS-EEND 원시 speakerId를 넘기면 resolveFinalLabels 조회가 전부 빗나가 재조정이 no-op이 된다.)
            let liveTimeline = liveSpeakerSegments.filter { $0.endSeconds > $0.startSeconds }
            let liveLabelMap = DiarizationSpeakerLabeling.makeLabelMap(from: liveTimeline)
            let liveLabeled = liveTimeline.compactMap { segment -> DiarizedSpeakerSegment? in
                guard let label = liveLabelMap[segment.speakerId] else {
                    return nil
                }
                return DiarizedSpeakerSegment(
                    speakerId: label,
                    startSeconds: segment.startSeconds,
                    endSeconds: segment.endSeconds
                )
            }
            let labelMap = LiveDiarizationReconciler.mapLabels(
                live: liveLabeled,
                final: finalLabeled
            )
            let finalLabels = LiveDiarizationReconciler.resolveFinalLabels(
                transcript: liveTranscript.map {
                    (
                        liveLabel: $0.speaker ?? "",
                        edited: editedSegmentIds.contains($0.id)
                    )
                },
                labelMap: labelMap
            )
            let resolvedTranscript = apply(labels: finalLabels, to: liveTranscript)

            let rawCentroids = VoiceprintMatching.centroids(from: diarization.embeddings)
            let speakerEmbeddings = rawCentroids.compactMap { rawCentroid -> MeetingRecord.MeetingSpeakerEmbedding? in
                guard let label = vbxLabelMap[rawCentroid.speakerId] else {
                    return nil
                }
                return MeetingRecord.MeetingSpeakerEmbedding(
                    speakerLabel: label,
                    embedding: rawCentroid.centroid,
                    embeddingModelID: FluidAudioOfflineDiarizationProvider.embeddingModelID
                )
            }.sorted { lhs, rhs in
                lhs.speakerLabel < rhs.speakerLabel
            }

            guard !enrolledVoiceprints.isEmpty else {
                Log.diarization.info(
                    "live diarization finalize complete transcriptSegments=\(resolvedTranscript.count, privacy: .public) finalSpeakerSegments=\(finalLabeled.count, privacy: .public) speakerEmbeddings=\(speakerEmbeddings.count, privacy: .public) identifiedSpeakers=\(0, privacy: .public)"
                )
                return (segments: resolvedTranscript, speakerEmbeddings: speakerEmbeddings)
            }

            let labeledCentroids = speakerEmbeddings.map {
                (speakerLabel: $0.speakerLabel, centroid: $0.embedding)
            }
            let identified = VoiceprintMatching.identifySpeakers(
                labeledCentroids: labeledCentroids,
                among: enrolledVoiceprints,
                embeddingModelID: FluidAudioOfflineDiarizationProvider.embeddingModelID,
                threshold: VoiceprintMatching.defaultIdentificationThreshold
            )

            var identifiedTranscript = resolvedTranscript
            var identifiedEmbeddings = speakerEmbeddings
            for (label, voiceprint) in identified.sorted(by: { lhs, rhs in lhs.key < rhs.key }) {
                let beforeTranscript = identifiedTranscript
                identifiedTranscript = replacingSpeakerInUneditedSegments(
                    label,
                    with: voiceprint.displayName,
                    in: identifiedTranscript,
                    editedSegmentIds: editedSegmentIds
                )
                // transcript에서 실제로 치환된 경우에만 embedding 라벨도 치환해 키 일관성을 지킨다.
                // 해당 라벨의 모든 segment가 사용자 편집으로 보존되면 transcript는 안 바뀌므로,
                // embedding을 실명으로 바꾸면 transcript("화자 N")와 어긋난다(사용자 편집 우선).
                guard identifiedTranscript != beforeTranscript else {
                    continue
                }
                identifiedEmbeddings = SpeakerLabelEditing.replacingSpeakerLabel(
                    label,
                    with: voiceprint.displayName,
                    in: identifiedEmbeddings
                ) ?? identifiedEmbeddings
            }

            Log.diarization.info(
                "live diarization finalize complete transcriptSegments=\(identifiedTranscript.count, privacy: .public) finalSpeakerSegments=\(finalLabeled.count, privacy: .public) speakerEmbeddings=\(identifiedEmbeddings.count, privacy: .public) identifiedSpeakers=\(identified.count, privacy: .public)"
            )
            return (segments: identifiedTranscript, speakerEmbeddings: identifiedEmbeddings)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let errorCase = Self.errorCase(error)
            let nsError = error as NSError
            Log.diarization.error(
                "live diarization finalize failed transcriptSegments=\(liveTranscript.count, privacy: .public) liveSpeakerSegments=\(liveSpeakerSegments.count, privacy: .public) editedSegments=\(editedSegmentIds.count, privacy: .public) enrolledVoiceprints=\(enrolledVoiceprints.count, privacy: .public) expectedSpeakers=\(expectedSpeakerCount ?? 0, privacy: .public) error=\(errorCase, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            throw error
        }
    }

    private static func errorCase(_ error: Error) -> String {
        String(describing: error).components(separatedBy: "(").first ?? String(describing: error)
    }

    private func apply(labels: [String], to transcript: [Segment]) -> [Segment] {
        transcript.enumerated().map { index, segment in
            guard labels.indices.contains(index) else {
                return segment
            }
            var updated = segment
            updated.speaker = SpeakerLabel.normalized(labels[index])
            return updated
        }
    }

    private func replacingSpeakerInUneditedSegments(
        _ source: String,
        with target: String,
        in segments: [Segment],
        editedSegmentIds: Set<Segment.ID>
    ) -> [Segment] {
        let editableSegments = segments.filter { !editedSegmentIds.contains($0.id) }
        let replacedEditableSegments = SpeakerLabelEditing.replacingSpeaker(
            source,
            with: target,
            in: editableSegments
        )
        var replacedByID: [Segment.ID: Segment] = [:]
        for segment in replacedEditableSegments {
            replacedByID[segment.id] = segment
        }

        return segments.map { segment in
            if editedSegmentIds.contains(segment.id) {
                return segment
            }
            return replacedByID[segment.id] ?? segment
        }
    }
}
