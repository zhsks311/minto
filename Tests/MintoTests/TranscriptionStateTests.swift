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

        // After 10 calls: segments 0-8 are committed (segment 9 is still pending)
        let committed = state.committedSegments
        #expect(committed.count == 9)
        for (index, segment) in committed.enumerated() {
            #expect(segment.text == "segment \(index)", "Order must be preserved at index \(index)")
        }
        #expect(state.pendingSegment?.text == "segment 9")
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

        // Fill to 101 committed (102 advanceWindow calls: first fills pending, rest commit)
        for i in 0..<102 {
            state.advanceWindow(newResult: makeResult(text: "s\(i)"))
        }

        // Give notification time to propagate
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(flushed, "Should post transcriptionNeedsFlush notification")
        #expect(state.committedSegments.count < 100, "Buffer should be cleared after flush")
    }

    @Test("recentCommittedText: 최근 3개 join")
    func recentCommittedTextJoinsLast3() {
        var state = TranscriptionState()
        let texts = ["one", "two", "three", "four", "five"]
        for text in texts {
            state.advanceWindow(newResult: makeResult(text: text))
        }
        // Committed: one, two, three, four (five is pending)
        #expect(state.recentCommittedText == "two three four")
    }
}
