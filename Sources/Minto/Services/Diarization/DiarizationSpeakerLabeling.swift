import Foundation

/// 화자 id → "화자 N" 표시 라벨 매핑. matcher와 품질 메트릭이 같은 번호를 쓰도록 단일 출처로 둔다.
enum DiarizationSpeakerLabeling {
    /// 등장 시각(가장 이른 startSeconds) 순으로 번호를 부여한다. DiarizationResult.segments의
    /// 배열 순서가 정렬을 보장하지 않으므로, 입력 순서가 아니라 시작 시각으로 안정 번호를 매겨야
    /// 같은 녹음·파라미터에서 실행마다 동일한 "화자 N"이 나온다(sweep 재현성).
    static func makeLabelMap(from segments: [DiarizedSpeakerSegment]) -> [String: String] {
        var earliestStart: [String: Double] = [:]
        for segment in segments {
            if let existing = earliestStart[segment.speakerId] {
                earliestStart[segment.speakerId] = min(existing, segment.startSeconds)
            } else {
                earliestStart[segment.speakerId] = segment.startSeconds
            }
        }
        let ordered = earliestStart.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }
        var labels: [String: String] = [:]
        for (index, entry) in ordered.enumerated() {
            labels[entry.key] = "화자 \(index + 1)"
        }
        return labels
    }
}
