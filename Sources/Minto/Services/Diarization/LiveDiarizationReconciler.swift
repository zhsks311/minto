import Foundation

/// 라이브 임시 화자 라벨을 저장 시 VBx 최종 라벨로 재조정하는 순수 알고리즘.
///
/// `docs/work/reconciliation-algorithm-spec.md`(Task 0b) 기준. 보이스프린트 실명·실제
/// transcript 시간 바인딩·저장경로 배선은 Phase 4b이며 여기 포함하지 않는다.
public enum LiveDiarizationReconciler {

    /// 라이브 화자라벨 → 최종(VBx) 화자라벨 매핑.
    ///
    /// 두 라벨의 시간 겹침 IOU 행렬을 만들고 그리디 최대 매칭(IOU 큰 쌍부터 1:1)으로 대응한다.
    /// 동점은 더 이른 등장(작은 startSeconds) 우선. 매칭 안 된 라이브 라벨은 맵에 없다(호출측 fallback).
    public static func mapLabels(
        live: [DiarizedSpeakerSegment],
        final: [DiarizedSpeakerSegment]
    ) -> [String: String] {
        let liveLabels = orderedLabels(live)
        let finalLabels = Set(final.map { $0.speakerId })
        guard !liveLabels.isEmpty, !finalLabels.isEmpty else {
            return [:]
        }

        let liveDuration = totalDurationByLabel(live)
        let finalDuration = totalDurationByLabel(final)
        let liveFirstStart = firstStartByLabel(live)

        struct Candidate {
            let liveLabel: String
            let finalLabel: String
            let iou: Double
            let liveStart: Double
        }

        var candidates: [Candidate] = []
        for liveLabel in liveLabels {
            for finalLabel in finalLabels {
                let overlap = overlapSeconds(
                    liveLabel: liveLabel,
                    finalLabel: finalLabel,
                    live: live,
                    final: final
                )
                guard overlap > 0 else {
                    continue
                }
                let union = (liveDuration[liveLabel] ?? 0) + (finalDuration[finalLabel] ?? 0) - overlap
                let iou = union > 0 ? overlap / union : 0
                candidates.append(
                    Candidate(
                        liveLabel: liveLabel,
                        finalLabel: finalLabel,
                        iou: iou,
                        liveStart: liveFirstStart[liveLabel] ?? .greatestFiniteMagnitude
                    )
                )
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.iou != rhs.iou {
                return lhs.iou > rhs.iou
            }
            return lhs.liveStart < rhs.liveStart
        }

        var map: [String: String] = [:]
        var usedFinal: Set<String> = []
        for candidate in candidates {
            if map[candidate.liveLabel] != nil || usedFinal.contains(candidate.finalLabel) {
                continue
            }
            map[candidate.liveLabel] = candidate.finalLabel
            usedFinal.insert(candidate.finalLabel)
        }
        return map
    }

    /// transcript segment별 최종 라벨 결정. 사용자가 편집한 라벨은 보존한다.
    public static func resolveFinalLabels(
        transcript: [(liveLabel: String, edited: Bool)],
        labelMap: [String: String]
    ) -> [String] {
        transcript.map { entry in
            if entry.edited {
                return entry.liveLabel
            }
            return labelMap[entry.liveLabel] ?? entry.liveLabel
        }
    }

    // MARK: - Helpers

    private static func orderedLabels(_ segments: [DiarizedSpeakerSegment]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for segment in segments.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            if seen.insert(segment.speakerId).inserted {
                ordered.append(segment.speakerId)
            }
        }
        return ordered
    }

    private static func totalDurationByLabel(_ segments: [DiarizedSpeakerSegment]) -> [String: Double] {
        var durations: [String: Double] = [:]
        for segment in segments {
            durations[segment.speakerId, default: 0] += max(0, segment.endSeconds - segment.startSeconds)
        }
        return durations
    }

    private static func firstStartByLabel(_ segments: [DiarizedSpeakerSegment]) -> [String: Double] {
        var firsts: [String: Double] = [:]
        for segment in segments {
            let current = firsts[segment.speakerId] ?? .greatestFiniteMagnitude
            firsts[segment.speakerId] = min(current, segment.startSeconds)
        }
        return firsts
    }

    private static func overlapSeconds(
        liveLabel: String,
        finalLabel: String,
        live: [DiarizedSpeakerSegment],
        final: [DiarizedSpeakerSegment]
    ) -> Double {
        let liveSegments = live.filter { $0.speakerId == liveLabel }
        let finalSegments = final.filter { $0.speakerId == finalLabel }
        var total = 0.0
        for liveSegment in liveSegments {
            for finalSegment in finalSegments {
                let overlap = min(liveSegment.endSeconds, finalSegment.endSeconds)
                    - max(liveSegment.startSeconds, finalSegment.startSeconds)
                total += max(0, overlap)
            }
        }
        return total
    }
}
