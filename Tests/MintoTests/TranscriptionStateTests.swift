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

    @Test("101번째 advanceWindow: flush 알림 발생 + 배열 초기화")
    func advanceWindowFlushesAt101() async {
        var state = TranscriptionState()
        nonisolated(unsafe) var flushed = false

        let observer = NotificationCenter.default.addObserver(
            forName: .transcriptionNeedsFlush,
            object: nil,
            queue: .main
        ) { _ in flushed = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        // 직접 커밋: 101번 호출 → 101번째에서 flush
        for i in 0..<101 {
            state.advanceWindow(newResult: makeResult(text: "s\(i)"))
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(flushed, "Should post transcriptionNeedsFlush notification")
        #expect(state.committedSegments.count < 100, "Buffer should be cleared after flush")
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
}
