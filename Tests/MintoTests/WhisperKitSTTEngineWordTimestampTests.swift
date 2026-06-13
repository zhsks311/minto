import Testing
@testable import MintoCore

@Suite("WhisperKitSTTEngine WordTimestamp mapping")
struct WhisperKitSTTEngineWordTimestampTests {
    @Test("WordTiming-like 값을 WordTimestamp로 변환한다")
    func mapsWordTimingSnapshots() {
        let mapped = WhisperKitSTTEngine.wordTimestamps(from: [
            WhisperWordTimingSnapshot(word: "안녕", start: 1.5, end: 2.0),
            WhisperWordTimingSnapshot(word: "하세요", start: 2.25, end: 3.0),
        ])

        #expect(mapped == [
            WordTimestamp(word: "안녕", start: 1.5, end: 2.0),
            WordTimestamp(word: "하세요", start: 2.25, end: 3.0),
        ])
    }

    @Test("nil WordTiming 입력은 nil words로 유지한다")
    func keepsNilWordTimingsNil() {
        #expect(WhisperKitSTTEngine.wordTimestamps(from: nil) == nil)
    }
}
