import Testing
@testable import MintoCore
import Foundation

@Suite("TranscriptionState Tests")
struct TranscriptionStateTests {

    func makeResult(text: String) -> TranscriptionResult {
        TranscriptionResult(
            segment: Segment(text: text, timestamp: Date(), duration: 1.0),
            isFinal: true
        )
    }

    @Test("advanceWindow 10회: 순서 역전 없음")
    func advanceWindowPreservesOrder() {
        var state = TranscriptionState()
        let texts = (0..<10).map { "segment \($0)" }

        for text in texts {
            state.advanceWindow(newResult: makeResult(text: text))
        }

        // 직접 커밋: 10번 호출 → 10개 모두 committed
        let committed = state.committedSegments
        #expect(committed.count == 10)
        for (index, segment) in committed.enumerated() {
            #expect(segment.text == "segment \(index)", "Order must be preserved at index \(index)")
        }
    }

    @Test("101구간: evict 없이 전부 유지(저장 record 전사 유실 방지)")
    func advanceWindowRetainsBeyond100() async {
        var state = TranscriptionState()
        nonisolated(unsafe) var flushed = false

        let observer = NotificationCenter.default.addObserver(
            forName: .transcriptionNeedsFlush,
            object: nil,
            queue: .main
        ) { _ in flushed = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        // 101번 커밋 — 과거엔 100 초과 시 evict(removeAll)됐으나, 이제 캡(5000)이라 전부 유지.
        for i in 0..<101 {
            state.advanceWindow(newResult: makeResult(text: "s\(i)"))
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(!flushed, "5000 미만에서는 flush(evict)되지 않아야 함")
        #expect(state.committedSegments.count == 101, "101구간이 유실 없이 모두 유지되어야 함")
    }

    @Test("replaceRange: 연속 구간을 교정본 1개로 병합")
    func replaceRangeMergesContiguous() {
        var state = TranscriptionState()
        for t in ["alpha", "bravo", "charlie"] {
            state.advanceWindow(newResult: makeResult(text: t))
        }
        #expect(state.committedSegments.count == 3)
        let ids = state.committedSegments.map(\.id)
        let firstTimestamp = state.committedSegments[0].timestamp

        state.replaceRange(ids: ids, correctedText: "교정된 한 문단")

        #expect(state.committedSegments.count == 1)
        #expect(state.committedSegments[0].text == "교정된 한 문단")
        #expect(state.committedSegments[0].timestamp == firstTimestamp)
        #expect(state.committedSegments[0].duration == 3.0)  // 1.0 × 3
    }

    @Test("replaceRange: 뒤쪽 일부만 병합하면 앞 구간과 순서 유지")
    func replaceRangePartialKeepsOrder() {
        var state = TranscriptionState()
        for t in ["alpha", "bravo", "charlie"] {
            state.advanceWindow(newResult: makeResult(text: t))
        }
        let ids = state.committedSegments.map(\.id)

        state.replaceRange(ids: [ids[1], ids[2]], correctedText: "BC병합")

        #expect(state.committedSegments.count == 2)
        #expect(state.committedSegments[0].text == "alpha")
        #expect(state.committedSegments[1].text == "BC병합")
        #expect(state.committedSegments[1].duration == 2.0)
    }

    @Test("replaceRange: 존재하지 않는 id는 무시(no-op)")
    func replaceRangeIgnoresMissingIds() {
        var state = TranscriptionState()
        state.advanceWindow(newResult: makeResult(text: "alpha"))
        let before = state.committedSegments

        state.replaceRange(ids: [UUID()], correctedText: "없는거")

        #expect(state.committedSegments.count == before.count)
        #expect(state.committedSegments[0].text == "alpha")
    }

    @Test("recentCommittedText: 최근 3개 join")
    func recentCommittedTextJoinsLast3() {
        var state = TranscriptionState()
        let texts = ["one", "two", "three", "four", "five"]
        for text in texts {
            state.advanceWindow(newResult: makeResult(text: text))
        }
        // 직접 커밋: 5개 모두 committed, 최근 3개 = three four five
        #expect(state.recentCommittedText == "three four five")
    }

    @Test("precedingText: 교정 배치 이전 텍스트만, 배치와 겹치지 않는다(BUG-1)")
    func precedingTextExcludesBatch() {
        var state = TranscriptionState()
        for text in ["one", "two", "three", "four", "five"] {
            state.advanceWindow(newResult: makeResult(text: text))
        }
        let committed = state.committedSegments      // one two three four five
        let batchIds = [committed[3].id, committed[4].id]  // four, five = 교정 대상
        // 배치(four,five) 바로 앞 최근 3개 = one two three. 배치 텍스트(four/five)는 절대 포함 안 됨.
        #expect(state.precedingText(beforeIds: batchIds) == "one two three")
    }

    @Test("precedingText: 배치를 못 찾으면 최근 maxSegments개로 폴백")
    func precedingTextFallsBackWhenIdsAbsent() {
        var state = TranscriptionState()
        for text in ["a", "b", "c", "d"] {
            state.advanceWindow(newResult: makeResult(text: text))
        }
        // 이미 교정·병합돼 id가 사라진 경우 → 맨 끝 3개로 폴백
        #expect(state.precedingText(beforeIds: [UUID()]) == "b c d")
    }
}
