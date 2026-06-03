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

    /// 여러 연속 segment를 교정된 단일 segment로 병합한다.
    /// (창 단위 배치 교정용 — 첫 segment의 id·timestamp를 유지하고 duration은 합산)
    /// ids는 committedSegments에 연속으로 존재한다고 가정한다. 일부가 없으면 있는 것만 병합하며,
    /// 하나도 없으면 no-op.
    public mutating func replaceRange(ids: [UUID], correctedText: String) {
        let idSet = Set(ids)
        guard let firstIdx = committedSegments.firstIndex(where: { idSet.contains($0.id) }) else {
            return
        }
        let members = committedSegments.filter { idSet.contains($0.id) }
        guard let first = members.first else {
            return
        }
        let totalDuration = members.reduce(0) { $0 + $1.duration }
        let merged = Segment(
            id: first.id,
            text: correctedText,
            timestamp: first.timestamp,
            duration: totalDuration
        )
        committedSegments.removeAll { idSet.contains($0.id) }
        committedSegments.insert(merged, at: firstIdx)
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

    /// 교정 배치(`ids`) **바로 앞**의 최근 `maxSegments`개 텍스트(교정 context 전용).
    ///
    /// `recentCommittedText`(맨 끝 3개)와 달리, 지금 교정 중인 배치와 **겹치지 않는** 직전 텍스트를
    /// 돌려준다. 배치 텍스트가 context로도 같이 들어가면 LLM이 그 문장을 출력에 그대로 에코·중복하기
    /// 쉬운데(교정 날조의 한 원인), 배치 이전 구간만 주면 그 표면을 없앤다.
    /// 배치를 못 찾으면(이미 교정·병합돼 id가 사라진 경우) 맨 끝 `maxSegments`개로 폴백한다.
    public func precedingText(beforeIds ids: [UUID], maxSegments: Int = 3) -> String {
        let idSet = Set(ids)
        guard let cutoff = committedSegments.firstIndex(where: { idSet.contains($0.id) }) else {
            return committedSegments.suffix(maxSegments).map(\.text).joined(separator: " ")
        }
        return committedSegments[..<cutoff].suffix(maxSegments).map(\.text).joined(separator: " ")
    }
}
