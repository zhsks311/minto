import Foundation

/// 전사 세그먼트(VAD 청크)를 word 타임스탬프 기준으로 문장 단위로 쪼개고, 각 조각에
/// 단어 단위 다수결 화자를 배정한다. TranscriptSpeakerMatcher가 청크 전체에 화자 1명만
/// 붙이는 한계(한 청크 내 화자 교대 시 소수 화자 소실)를 word-level 재배정으로 보완한다.
///
/// 순수 함수다. 호출부 상태(editedSpeakerSegmentIds 등)에 의존하지 않도록 보존 대상 id는
/// preserveSegmentIds로 주입받는다. ML·네트워크 없이 합성 입력만으로 전부 단위 테스트 가능.
public struct SentenceSpeakerSplitter: Sendable {
    /// 같은 화자 내에서 이 시간(초) 이상 침묵 갭이 있으면 문장 경계로 본다.
    public let silenceGapSeconds: Double
    /// 이보다 짧은 화자 run은 독립 화자로 인정하지 않고 인접 화자에 흡수한다.
    public let minWordsPerSpeakerRun: Int

    /// 문장 종결 부호. 마지막 글자가 이 집합에 속하면 그 단어 뒤를 문장 경계로 본다.
    private static let sentenceTerminators: Set<Character> = [".", "?", "!", "。", "…"]

    public init(silenceGapSeconds: Double = 0.5, minWordsPerSpeakerRun: Int = 2) {
        self.silenceGapSeconds = silenceGapSeconds
        self.minWordsPerSpeakerRun = minWordsPerSpeakerRun
    }

    public func split(
        transcript: [Segment],
        diarizedSegments: [DiarizedSpeakerSegment],
        meetingStart: Date,
        preserveSegmentIds: Set<UUID> = []
    ) -> [Segment] {
        let timeline = diarizedSegments.filter { $0.endSeconds > $0.startSeconds }
        let labelMap = DiarizationSpeakerLabeling.makeLabelMap(from: timeline)

        return transcript.flatMap { segment in
            splitSegment(
                segment,
                timeline: timeline,
                labelMap: labelMap,
                meetingStart: meetingStart,
                preserveSegmentIds: preserveSegmentIds
            )
        }
    }

    private func splitSegment(
        _ segment: Segment,
        timeline: [DiarizedSpeakerSegment],
        labelMap: [String: String],
        meetingStart: Date,
        preserveSegmentIds: Set<UUID>
    ) -> [Segment] {
        guard let words = segment.words, !words.isEmpty else { return [segment] }
        guard !timeline.isEmpty else { return [segment] }
        guard !preserveSegmentIds.contains(segment.id) else { return [segment] }

        let segmentStart = segment.timestamp.timeIntervalSince(meetingStart)

        // 1. 단어별 화자 라벨 배정 (겹침이 없으면 nil)
        var speakers: [String?] = words.map { word in
            let absoluteStart = segmentStart + word.start
            let absoluteEnd = segmentStart + word.end
            return bestSpeaker(
                start: absoluteStart,
                end: absoluteEnd,
                timeline: timeline
            ).flatMap { labelMap[$0] }
        }

        // 2. nil 채우기(앞→뒤, 그 다음 뒤→앞). 전부 nil이면 폴백.
        guard fillNilSpeakers(&speakers) else { return [segment] }

        // 3. 짧은 화자 run 흡수
        absorbShortRuns(&speakers)

        // 4. 문장 경계 분할 → sub-run 인덱스 묶음
        let runs = sentenceRuns(words: words, speakers: speakers)

        // 5. 각 sub-run을 Segment로. 첫 sub-run만 원본 id 승계.
        var result: [Segment] = []
        result.reserveCapacity(runs.count)
        for (runIndex, run) in runs.enumerated() {
            guard let built = buildSegment(
                from: run,
                words: words,
                speakers: speakers,
                originalSegment: segment,
                inheritsOriginalId: runIndex == 0
            ) else { continue }
            result.append(built)
        }
        // 빈 텍스트만 나와 전부 버려졌다면 원본을 보존(전사 유실 방지)
        return result.isEmpty ? [segment] : result
    }

    /// 절대 구간 [start, end]와 가장 많이 겹치는 화자 speakerId. 동률은 earliestStart→speakerId.
    private func bestSpeaker(
        start: Double,
        end: Double,
        timeline: [DiarizedSpeakerSegment]
    ) -> String? {
        guard end > start else { return nil }
        var seconds: [String: Double] = [:]
        var earliestStart: [String: Double] = [:]
        for diarized in timeline {
            let overlap = max(0, min(end, diarized.endSeconds) - max(start, diarized.startSeconds))
            guard overlap > 0 else { continue }
            seconds[diarized.speakerId, default: 0] += overlap
            earliestStart[diarized.speakerId] = min(
                earliestStart[diarized.speakerId] ?? .infinity,
                diarized.startSeconds
            )
        }
        return seconds.keys.max { lhs, rhs in
            let lhsSeconds = seconds[lhs] ?? 0
            let rhsSeconds = seconds[rhs] ?? 0
            if lhsSeconds != rhsSeconds { return lhsSeconds < rhsSeconds }
            let lhsStart = earliestStart[lhs] ?? .infinity
            let rhsStart = earliestStart[rhs] ?? .infinity
            if lhsStart != rhsStart { return lhsStart > rhsStart }
            return lhs > rhs
        }
    }

    /// nil 단어를 가장 가까운 비-nil 이웃 화자로 채운다. 전부 nil이면 false(폴백 신호).
    private func fillNilSpeakers(_ speakers: inout [String?]) -> Bool {
        guard speakers.contains(where: { $0 != nil }) else { return false }
        var lastSeen: String?
        for index in speakers.indices {
            if let speaker = speakers[index] {
                lastSeen = speaker
            } else if let lastSeen {
                speakers[index] = lastSeen
            }
        }
        // 선두에 남은 nil은 첫 비-nil로 역채움
        if let firstNonNil = speakers.first(where: { $0 != nil }) ?? nil {
            for index in speakers.indices where speakers[index] == nil {
                speakers[index] = firstNonNil
            }
        }
        return true
    }

    /// minWordsPerSpeakerRun 미만 run을 앞 run 화자(없으면 뒤 run 화자)로 재배정한다.
    private func absorbShortRuns(_ speakers: inout [String?]) {
        var changed = true
        while changed {
            changed = false
            let runs = contiguousRuns(speakers)
            guard runs.count > 1 else { return }
            for (runIndex, run) in runs.enumerated() where run.count < minWordsPerSpeakerRun {
                let replacement: String?
                if runIndex > 0 {
                    replacement = speakers[runs[runIndex - 1].first!]
                } else {
                    replacement = speakers[runs[runIndex + 1].first!]
                }
                guard let replacement, replacement != speakers[run.first!] else { continue }
                for wordIndex in run {
                    speakers[wordIndex] = replacement
                }
                changed = true
                break
            }
        }
    }

    /// 같은 화자 값(nil 포함)이 연속인 인덱스 묶음들.
    private func contiguousRuns(_ speakers: [String?]) -> [[Int]] {
        var runs: [[Int]] = []
        for index in speakers.indices {
            if let last = runs.last, speakers[last.first!] == speakers[index] {
                runs[runs.count - 1].append(index)
            } else {
                runs.append([index])
            }
        }
        return runs
    }

    /// 화자 전환·문장종결 부호·침묵 갭에서 분할한 단어 인덱스 묶음들.
    private func sentenceRuns(words: [WordTimestamp], speakers: [String?]) -> [[Int]] {
        var runs: [[Int]] = []
        for index in words.indices {
            if index == 0 {
                runs.append([index])
                continue
            }
            if isBoundary(at: index, words: words, speakers: speakers) {
                runs.append([index])
            } else {
                runs[runs.count - 1].append(index)
            }
        }
        return runs
    }

    private func isBoundary(at index: Int, words: [WordTimestamp], speakers: [String?]) -> Bool {
        if speakers[index] != speakers[index - 1] {
            return true
        }
        if endsSentence(words[index - 1].word) {
            return true
        }
        if words[index].start - words[index - 1].end >= silenceGapSeconds {
            return true
        }
        return false
    }

    private func endsSentence(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespaces).last else { return false }
        return Self.sentenceTerminators.contains(last)
    }

    private func buildSegment(
        from run: [Int],
        words: [WordTimestamp],
        speakers: [String?],
        originalSegment: Segment,
        inheritsOriginalId: Bool
    ) -> Segment? {
        guard let firstIndex = run.first, let lastIndex = run.last else { return nil }
        let runWords = run.map { words[$0] }
        let text = runWords.map(\.word).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        let firstStart = words[firstIndex].start
        let rebasedWords = runWords.map { word in
            WordTimestamp(word: word.word, start: word.start - firstStart, end: word.end - firstStart)
        }

        return Segment(
            id: inheritsOriginalId ? originalSegment.id : UUID(),
            text: text,
            timestamp: originalSegment.timestamp.addingTimeInterval(firstStart),
            duration: words[lastIndex].end - firstStart,
            speaker: speakers[firstIndex],
            words: rebasedWords
        )
    }
}
