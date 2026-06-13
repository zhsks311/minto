import Foundation
import Testing
@testable import MintoCore

@Suite("TranscriptNormalizer Tests")
struct TranscriptNormalizerTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("incomplete chunk ending with particle merges with next segment")
    func mergesParticleEndingWithNextSegment() {
        let segments = [
            segment("여기는 똑같이 DDL를 정리를 했다고 가정을 하고 이렇게 XML을", offset: 0),
            segment("파일을 추가를 해주게 됩니다. XML이나 JSON 같은 파일로도 관리할 수 있어요.", offset: 30),
        ]

        let normalized = TranscriptNormalizer.normalize(segments)

        #expect(normalized.count == 1)
        #expect(normalized[0].text.contains("XML을 파일을 추가"))
        #expect(normalized[0].timestamp == segments[0].timestamp)
        #expect(normalized[0].duration == 60)
    }

    @Test("incomplete connective ending merges with next segment")
    func mergesConnectiveEndingWithNextSegment() {
        let segments = [
            segment("스키마가 변경될 때마다", offset: 0),
            segment("직접 수행하지 않고 자동으로 맞춰줘서 편할 것 같긴 합니다.", offset: 30),
        ]

        let normalized = TranscriptNormalizer.normalize(segments)

        #expect(normalized.count == 1)
        #expect(normalized[0].text == "스키마가 변경될 때마다 직접 수행하지 않고 자동으로 맞춰줘서 편할 것 같긴 합니다.")
    }

    @Test("incomplete ending with 는데 merges with next segment")
    func mergesNeundeEndingWithNextSegment() {
        let segments = [
            segment("노트북에 별도의 주장하는 바를 이렇게 붙여 놓으셨는데", offset: 0),
            segment("양당 간사님들이 상의를 좀 하시고 떼고 난 다음에 시작하겠습니다.", offset: 15),
        ]

        let normalized = TranscriptNormalizer.normalize(segments)

        #expect(normalized.count == 1)
        #expect(normalized[0].text.contains("놓으셨는데 양당 간사님들이"))
    }

    @Test("complete sentence stays separated")
    func keepsCompleteSentenceSeparated() {
        let segments = [
            segment("컬럼이 새롭게 추가된 것을 확인할 수 있습니다.", offset: 0),
            segment("히스토리 테이블에는 어떤 일들이 적재될까요?", offset: 30),
        ]

        let normalized = TranscriptNormalizer.normalize(segments)

        #expect(normalized.count == 2)
    }

    @Test("max length prevents over-merging")
    func maxLengthPreventsOverMerging() {
        let segments = [
            segment(String(repeating: "가", count: 420) + "을", offset: 0),
            segment("다음 문장입니다.", offset: 30),
        ]

        let normalized = TranscriptNormalizer.normalize(segments)

        #expect(normalized.count == 2)
    }

    @Test("speaker가 다르면 incomplete ending이어도 병합하지 않는다")
    func differentSpeakerPreventsMerge() {
        let segments = [
            segment("스키마가 변경될 때마다", offset: 0, speaker: "나"),
            segment("직접 수행하지 않고 자동으로 맞춰줘서 편합니다.", offset: 30, speaker: "상대"),
        ]

        let normalized = TranscriptNormalizer.normalize(segments)

        #expect(normalized.count == 2)
        #expect(normalized.map(\.speaker) == ["나", "상대"])
    }

    @Test("speaker가 같으면 병합하고 speaker를 보존한다")
    func sameSpeakerMergesAndPreservesSpeaker() {
        let segments = [
            segment("스키마가 변경될 때마다", offset: 0, speaker: "나"),
            segment("직접 수행하지 않고 자동으로 맞춰줘서 편합니다.", offset: 30, speaker: "나"),
        ]

        let normalized = TranscriptNormalizer.normalize(segments)

        #expect(normalized.count == 1)
        #expect(normalized[0].speaker == "나")
        #expect(normalized[0].text.contains("때마다 직접 수행하지 않고"))
    }

    @MainActor
    @Test("makeRecord stores normalized transcript")
    func makeRecordStoresNormalizedTranscript() {
        let segments = [
            segment("스키마가 변경될 때마다", offset: 0),
            segment("직접 수행하지 않고 자동으로 맞춰주는 흐름입니다.", offset: 30),
        ]

        let record = AppDelegate.makeRecord(
            summary: MeetingSummary(title: "DB 형상관리"),
            segments: segments,
            topic: "db 스키마 관리",
            duration: 60
        )

        #expect(record.transcript.count == 1)
        #expect(record.transcript[0].text.contains("때마다 직접 수행"))
        #expect(record.title == "DB 형상관리")
    }

    @MainActor
    @Test("요약이 없어도 저장·export는 전사를 원문 fallback으로 보존한다")
    func emptySummaryKeepsTranscriptForRecordAndExport() {
        let segments = [
            segment("마지막으로 남은 전사입니다.", offset: 0),
        ]

        let record = AppDelegate.makeRecord(
            summary: MeetingSummary(),
            segments: segments,
            topic: "주간 회의",
            duration: 30
        )
        let markdown = MeetingExporter.markdown(
            for: MeetingResult(
                title: record.title,
                metaText: "",
                summary: record.summary,
                transcript: record.transcript.map {
                    MeetingResult.TranscriptLine(time: "00:00", text: $0.text)
                }
            )
        )

        #expect(!record.isEmpty)
        #expect(record.title == "주간 회의")
        #expect(record.transcript.map(\.text) == ["마지막으로 남은 전사입니다."])
        #expect(markdown.contains("## 전사"))
        #expect(markdown.contains("마지막으로 남은 전사입니다."))
    }

    private func segment(_ text: String, offset: TimeInterval, speaker: String? = nil) -> Segment {
        Segment(text: text, timestamp: baseDate.addingTimeInterval(offset), duration: 30, speaker: speaker)
    }
}
