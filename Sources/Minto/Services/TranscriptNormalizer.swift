import Foundation

enum TranscriptNormalizer {
    private static let defaultMaxCharacters = 420
    private static let defaultMaxDuration: TimeInterval = 90
    private static let defaultMaxGap: TimeInterval = 120

    static func normalize(
        _ segments: [Segment],
        maxCharacters: Int = defaultMaxCharacters,
        maxDuration: TimeInterval = defaultMaxDuration,
        maxGap: TimeInterval = defaultMaxGap
    ) -> [Segment] {
        var normalized: [Segment] = []
        for segment in segments where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard var current = normalized.popLast() else {
                normalized.append(trimmed(segment))
                continue
            }

            let next = trimmed(segment)
            if shouldMerge(current, next, maxCharacters: maxCharacters, maxDuration: maxDuration, maxGap: maxGap) {
                current = merge(current, next)
            } else {
                normalized.append(current)
                current = next
            }
            normalized.append(current)
        }
        return normalized
    }

    static func isLikelyIncompleteEnding(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasSuffix("...") || trimmed.hasSuffix("…") {
            return true
        }
        if [".", "?", "!", "。", "？", "！"].contains(where: { trimmed.hasSuffix($0) }) {
            return false
        }

        let lastWord = trimmed.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? trimmed
        let lowercasedLastWord = lastWord.lowercased()
        let danglingWords: Set<String> = [
            "이제", "아까", "조금", "뭐", "그", "저", "요", "auto", "tpm분",
        ]
        if danglingWords.contains(lowercasedLastWord) {
            return true
        }

        let danglingSuffixes = [
            "을", "를", "은", "는", "이", "가", "에", "에서", "으로", "로",
            "와", "과", "하고", "이며", "이고", "인데", "는데", "지만", "면서", "다가",
            "마다", "처럼", "까지", "부터", "보다", "한테", "에게", "라고",
            "이라는", "라는", "있는", "했던", "되면", "되다가", "측면에서",
            "퍼블릭하게", "자세하게", "최신이고",
        ]
        return danglingSuffixes.contains { lastWord.hasSuffix($0) }
    }

    private static func shouldMerge(
        _ current: Segment,
        _ next: Segment,
        maxCharacters: Int,
        maxDuration: TimeInterval,
        maxGap: TimeInterval
    ) -> Bool {
        guard current.speaker == next.speaker else { return false }
        guard isLikelyIncompleteEnding(current.text) else { return false }

        let combinedLength = current.text.count + 1 + next.text.count
        guard combinedLength <= maxCharacters else { return false }
        guard current.duration + next.duration <= maxDuration else { return false }

        let currentEnd = current.timestamp.addingTimeInterval(current.duration)
        let gap = next.timestamp.timeIntervalSince(currentEnd)
        guard gap <= maxGap else { return false }
        return true
    }

    private static func merge(_ current: Segment, _ next: Segment) -> Segment {
        let text = [current.text, next.text]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return Segment(
            id: current.id,
            text: text,
            timestamp: current.timestamp,
            duration: current.duration + next.duration,
            speaker: current.speaker,
            words: mergedWords(current.words, next.words)
        )
    }

    private static func trimmed(_ segment: Segment) -> Segment {
        Segment(
            id: segment.id,
            text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: segment.timestamp,
            duration: segment.duration,
            speaker: segment.speaker,
            words: segment.words
        )
    }

    private static func mergedWords(_ current: [WordTimestamp]?, _ next: [WordTimestamp]?) -> [WordTimestamp]? {
        guard current != nil || next != nil else { return nil }
        return (current ?? []) + (next ?? [])
    }
}
