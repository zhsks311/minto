import Foundation

/// 저장 시 아카이브 오디오에 offline VBx를 재실행해 화자 라벨을 확정한다(방법 A).
///
/// VBx 화자 세그먼트를 `TranscriptSpeakerMatcher`로 transcript에 직접 배정한다(시간 겹침).
/// 라이브(LS-EEND) 라벨 식별자에 묶지 않으므로, 최종 화자 수가 VBx의 정확한 카운트를 따른다.
/// (방법 B[mapLabels 연속성]는 최종 카운트를 라이브 카운트에 묶어 다화자를 과소추정시켰다 — 실측으로 A 채택.)
/// 사용자가 라이브 중 편집한 라벨은 VBx 배정으로 덮지 않는다.
public struct LiveDiarizationFinalizeUseCase: Sendable {
    private static let finalSpeakerMinimumOverlapRatio: Double = 0

    private let diarizer: any SegmentEmbeddingDiarizing

    public init(diarizer: any SegmentEmbeddingDiarizing) {
        self.diarizer = diarizer
    }

    public func finalize(
        audioFileURL: URL,
        liveTranscript: [Segment],
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
            "live diarization finalize start transcriptSegments=\(liveTranscript.count, privacy: .public) editedSegments=\(editedSegmentIds.count, privacy: .public) enrolledVoiceprints=\(enrolledVoiceprints.count, privacy: .public) expectedSpeakers=\(expectedSpeakerCount ?? 0, privacy: .public)"
        )

        do {
            let diarization = try await diarizer.diarizeWithSegmentsAndEmbeddings(audioFileURL: audioFileURL)
            let vbxTimeline = diarization.segments.filter { $0.endSeconds > $0.startSeconds }
            let vbxLabelMap = DiarizationSpeakerLabeling.makeLabelMap(from: vbxTimeline)
            let vbxSpeakerCount = Set(vbxLabelMap.values).count

            // 방법 A: VBx 세그먼트를 시간 겹침으로 transcript에 직접 배정("화자 N"). import과 동일 매처.
            // assignSpeakers는 내부적으로 makeLabelMap(vbxTimeline)을 쓰므로 위 vbxLabelMap과 라벨 공간이 일치한다
            // → transcript 라벨과 speakerEmbeddings 라벨 키가 정렬된다.
            let matched = TranscriptSpeakerMatcher(
                minimumOverlapRatio: Self.finalSpeakerMinimumOverlapRatio
            ).assignSpeakers(
                diarizedSegments: diarization.segments,
                transcript: liveTranscript,
                meetingStart: meetingStart
            )
            var matchedById: [Segment.ID: Segment] = [:]
            for segment in matched {
                matchedById[segment.id] = segment
            }
            // 사용자 편집 라벨은 VBx 배정으로 덮지 않는다.
            let matchedTranscript = liveTranscript.map { segment -> Segment in
                if editedSegmentIds.contains(segment.id) {
                    return segment
                }
                guard let matched = matchedById[segment.id],
                      SpeakerLabel.normalized(matched.speaker) != nil else {
                    return segment
                }
                return matched
            }

            // 문장 단위 화자 분할: word 타임스탬프로 화자 전환·문장 경계에서 세그먼트를 쪼개고
            // 단어 단위 다수결로 화자를 재배정한다. VBx 타임라인을 직접 재소비하므로 라벨 공간이
            // 위 매처와 같다("화자 N"=vbxLabelMap). 편집 세그먼트는 분할하지 않아 id·라벨이 보존된다
            // → 아래 voiceprint 실명 치환의 편집 스킵(editedSegmentIds)이 그대로 작동한다.
            // words==nil(SpeechAnalyzer 등) 세그먼트는 폴백해 매처 결과를 그대로 유지(회귀 0).
            let resolvedTranscript = SentenceSpeakerSplitter().split(
                transcript: matchedTranscript,
                diarizedSegments: diarization.segments,
                meetingStart: meetingStart,
                preserveSegmentIds: editedSegmentIds
            )

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
                    "live diarization finalize complete transcriptSegments=\(resolvedTranscript.count, privacy: .public) vbxSpeakers=\(vbxSpeakerCount, privacy: .public) speakerEmbeddings=\(speakerEmbeddings.count, privacy: .public) identifiedSpeakers=\(0, privacy: .public)"
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
                "live diarization finalize complete transcriptSegments=\(identifiedTranscript.count, privacy: .public) vbxSpeakers=\(vbxSpeakerCount, privacy: .public) speakerEmbeddings=\(identifiedEmbeddings.count, privacy: .public) identifiedSpeakers=\(identified.count, privacy: .public)"
            )
            return (segments: identifiedTranscript, speakerEmbeddings: identifiedEmbeddings)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let errorCase = Self.errorCase(error)
            let nsError = error as NSError
            Log.diarization.error(
                "live diarization finalize failed transcriptSegments=\(liveTranscript.count, privacy: .public) editedSegments=\(editedSegmentIds.count, privacy: .public) enrolledVoiceprints=\(enrolledVoiceprints.count, privacy: .public) expectedSpeakers=\(expectedSpeakerCount ?? 0, privacy: .public) error=\(errorCase, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            throw error
        }
    }

    private static func errorCase(_ error: Error) -> String {
        String(describing: error).components(separatedBy: "(").first ?? String(describing: error)
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
