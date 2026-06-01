import Foundation

public struct TranscriptionState: Sendable {
    public private(set) var committedSegments: [Segment] = []

    public init() {}

    /// VAD 청크 단위 커밋: 결과 도착 즉시 확정
    public mutating func advanceWindow(newResult: TranscriptionResult) {
        let newText = newResult.segment.text

        // 마지막 커밋과 유사한 텍스트면 skip (중복 방지)
        if let last = committedSegments.last, isSimilar(newText, last.text) {
            return
        }

        committedSegments.append(newResult.segment)

        if committedSegments.count > 100 {
            NotificationCenter.default.post(
                name: .transcriptionNeedsFlush,
                object: committedSegments
            )
            committedSegments.removeAll()
        }
    }

    /// LLM 교정 결과로 특정 segment의 텍스트를 교체한다.
    public mutating func updateSegmentText(id: UUID, newText: String) {
        guard let idx = committedSegments.firstIndex(where: { $0.id == id }) else { return }
        let old = committedSegments[idx]
        committedSegments[idx] = Segment(id: old.id, text: newText, timestamp: old.timestamp, duration: old.duration)
    }

    private func isSimilar(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        let norm: (String) -> String = {
            $0.lowercased()
              .replacingOccurrences(of: " ", with: "")
              .replacingOccurrences(of: ".", with: "")
              .replacingOccurrences(of: ",", with: "")
              .replacingOccurrences(of: "?", with: "")
              .replacingOccurrences(of: "!", with: "")
        }
        let na = norm(a), nb = norm(b)
        if na == nb { return true }
        if na.contains(nb) || nb.contains(na) { return true }
        // character bigram Jaccard > 0.75
        let bg: (String) -> Set<String> = { s in
            Set(zip(s, s.dropFirst()).map { String($0) + String($1) })
        }
        let ba = bg(na), bb = bg(nb)
        let union = ba.union(bb).count
        guard union > 0 else { return false }
        return Double(ba.intersection(bb).count) / Double(union) > 0.75
    }

    /// whisper initial_prompt 주입용: 최근 3 segment 텍스트
    public var recentCommittedText: String {
        committedSegments.suffix(3).map(\.text).joined(separator: " ")
    }
}
