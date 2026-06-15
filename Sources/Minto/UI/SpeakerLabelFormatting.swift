import Foundation

/// 전사 줄 화자 라벨 정규화. 공백뿐이거나 빈 라벨은 nil로 취급해 표시하지 않는다.
/// 전사 렌더 뷰 3곳(overlay/library/summary)이 같은 규칙을 쓰도록 단일 출처로 둔다.
enum SpeakerLabel {
    static func normalized(_ speaker: String?) -> String? {
        guard let trimmed = speaker?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum SpeakerLabelEditing {
    static func labels(in segments: [Segment]) -> [String] {
        var seen = Set<String>()
        var labels: [String] = []
        for segment in segments {
            guard let label = SpeakerLabel.normalized(segment.speaker),
                  !seen.contains(label) else {
                continue
            }
            seen.insert(label)
            labels.append(label)
        }
        return labels
    }

    static func replacingSpeaker(
        _ source: String,
        with target: String,
        in segments: [Segment]
    ) -> [Segment] {
        guard let sourceLabel = SpeakerLabel.normalized(source),
              let targetLabel = SpeakerLabel.normalized(target),
              sourceLabel != targetLabel else {
            return segments
        }

        return segments.map { segment in
            guard SpeakerLabel.normalized(segment.speaker) == sourceLabel else {
                return segment
            }
            var updated = segment
            updated.speaker = targetLabel
            return updated
        }
    }
}
