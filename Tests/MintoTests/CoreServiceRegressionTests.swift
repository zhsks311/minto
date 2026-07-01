import Foundation
import Testing
@testable import MintoCore

/// 핵심 서비스 연결 계약 회귀테스트.
/// 서비스별 세부 알고리즘은 각 단위 테스트가 맡고, 여기서는 저장 → 검색 → 내보내기 경계가 함께 깨지지 않는지 본다.
@MainActor
@Suite("Core service regression", .serialized)
struct CoreServiceRegressionTests {

    @Test("저장된 회의는 reload 후 검색 가능하고 Markdown으로 내보낼 수 있다")
    func savedMeetingRemainsSearchableAndExportableAfterReload() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = sampleRecord()

        let store = MeetingStore(directory: directory)
        #expect(store.save(record) == .success)

        let reloadedStore = MeetingStore(directory: directory)
        let loaded = try #require(reloadedStore.meetings.first)
        #expect(loaded.id == record.id)
        #expect(loaded.summaryGlossary == "Minto = 회의 기록 앱")
        #expect(loaded.document?.contains("doconlytoken") == true)
        #expect(loaded.transcript.first?.speaker == "화자*1")
        #expect(loaded.transcript.first?.words == [WordTimestamp(word: "결제", start: 5.0, end: 5.4)])
        #expect(loaded.speakerEmbeddings?.first?.speakerLabel == "화자*1")

        let index = try #require(MeetingSearchIndexStore(directory: directory).load())
        expectContainsResult(in: index, query: "출시 리스크", meetingID: record.id)
        expectContainsResult(in: index, query: "베타 배포", meetingID: record.id)
        expectContainsResult(in: index, query: "지민 금요일", meetingID: record.id)
        expectContainsResult(in: index, query: "doconlytoken", meetingID: record.id)
        expectContainsResult(in: index, query: "결제 플로우", meetingID: record.id)

        let result = MeetingResult.from(loaded)
        let markdown = MeetingExporter.markdown(for: result)
        #expect(markdown.contains("# 제품 출시 회의"))
        #expect(markdown.contains("런칭 전 결제 플로우와 검색 회귀를 점검했다."))
        #expect(markdown.contains("## 결정사항"))
        #expect(markdown.contains("베타 배포는 금요일 오전에 진행"))
        #expect(markdown.contains("## 할 일"))
        #expect(markdown.contains("체크리스트 정리"))
        #expect(markdown.contains("## 미해결 질문"))
        #expect(markdown.contains("롤백 기준"))
        #expect(markdown.contains("## 회의 자료"))
        #expect(markdown.contains("doconlytoken"))
        #expect(markdown.contains("## 전사"))
        #expect(markdown.contains(#"**[00:00]** **화자\*1:** 결제 플로우를 확인했습니다."#))
        #expect(markdown.contains("**[00:08]** 검색 회귀도 봐야 합니다."))
    }

    @Test("새 optional 필드가 없는 레거시 회의 JSON도 로드·검색·내보내기 된다")
    func legacyMeetingRecordStillLoadsAndExportsWithoutNewOptionalFields() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let legacyJSON = """
        {
          "id": "\(id.uuidString)",
          "title": "레거시 회의",
          "startedAt": "2026-06-30T09:00:00Z",
          "durationSeconds": 42,
          "topic": "이전 저장 파일",
          "summary": {
            "leadAnswer": "기존 요약은 유지된다.",
            "decisions": [{ "text": "기존 결정", "time": "00:10" }]
          },
          "transcript": [{
            "id": "33333333-3333-3333-3333-333333333333",
            "text": "레거시 전사",
            "timestamp": "2026-06-30T09:00:05Z",
            "duration": 3
          }]
        }
        """
        try Data(legacyJSON.utf8).write(to: directory.appendingPathComponent("\(id.uuidString).json"))

        let store = MeetingStore(directory: directory)
        let loaded = try #require(store.meetings.first)
        #expect(store.corruptedCount == 0)
        #expect(loaded.id == id)
        #expect(loaded.summaryGlossary == nil)
        #expect(loaded.document == nil)
        #expect(loaded.audioFileName == nil)
        #expect(loaded.speakerEmbeddings == nil)
        #expect(loaded.transcript.first?.speaker == nil)
        #expect(loaded.transcript.first?.words == nil)

        let index = try #require(MeetingSearchIndexStore(directory: directory).load())
        expectContainsResult(in: index, query: "레거시 전사", meetingID: id)

        let markdown = MeetingExporter.markdown(for: MeetingResult.from(loaded))
        #expect(markdown.contains("# 레거시 회의"))
        #expect(markdown.contains("기존 요약은 유지된다."))
        #expect(markdown.contains("기존 결정"))
        #expect(markdown.contains("**[00:00]** 레거시 전사"))
        #expect(!markdown.contains("## 회의 자료"))
    }

    @Test("손상 회의 파일은 유효 회의 목록과 검색 인덱스를 막지 않는다")
    func corruptRecordDoesNotBlockValidRecordsOrSearchIndex() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let valid = sampleRecord(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
        let validData = try MeetingRecordCoding.makeEncoder().encode(valid)
        try validData.write(to: directory.appendingPathComponent("\(valid.id.uuidString).json"))
        try Data("{ broken json".utf8).write(to: directory.appendingPathComponent("broken.json"))

        let store = MeetingStore(directory: directory)

        #expect(store.corruptedCount == 1)
        #expect(store.meetings.map(\.id) == [valid.id])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("broken.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("quarantine/broken.json").path))

        let index = try #require(MeetingSearchIndexStore(directory: directory).load())
        expectContainsResult(in: index, query: "결제 플로우", meetingID: valid.id)
        #expect(index.chunks.allSatisfy { $0.meetingID == valid.id })
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("minto-core-regression-\(UUID().uuidString)", isDirectory: true)
    }

    private func sampleRecord(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    ) -> MeetingRecord {
        let startedAt = Date(timeIntervalSince1970: 1_783_000_000)
        return MeetingRecord(
            id: id,
            title: "제품 출시 회의",
            startedAt: startedAt,
            durationSeconds: 120,
            topic: "출시 리스크 점검",
            summary: MeetingSummary(
                title: "제품 출시 회의",
                leadQuestion: "이번 출시에서 막아야 할 회귀는?",
                leadAnswer: "런칭 전 결제 플로우와 검색 회귀를 점검했다.",
                sections: [
                    .init(
                        title: "1. 결제 플로우 확인",
                        time: "00:20",
                        points: [.init(text: "결제 성공과 실패 상태를 모두 확인한다.", subPoints: ["영수증 화면", "재시도 버튼"])]
                    )
                ],
                keywords: ["출시", "결제", "검색"],
                decisions: [.init(text: "베타 배포는 금요일 오전에 진행", time: "00:40")],
                actionItems: [.init(task: "체크리스트 정리", owner: "지민", due: "금요일", time: "01:00")],
                openQuestions: [.init(text: "롤백 기준은 운영팀과 추가 확인", time: "01:20")]
            ),
            summaryGlossary: "Minto = 회의 기록 앱",
            document: "출시 문서 첫 문단\n\n첨부 문서 전용 토큰 doconlytoken",
            transcript: [
                Segment(
                    id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                    text: "결제 플로우를 확인했습니다.",
                    timestamp: startedAt.addingTimeInterval(5),
                    duration: 4,
                    speaker: "화자*1",
                    words: [WordTimestamp(word: "결제", start: 5.0, end: 5.4)]
                ),
                Segment(
                    id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                    text: "검색 회귀도 봐야 합니다.",
                    timestamp: startedAt.addingTimeInterval(13),
                    duration: 3
                )
            ],
            speakerEmbeddings: [
                .init(speakerLabel: "화자*1", embedding: [1, 0, 0], embeddingModelID: "test-embedding")
            ]
        )
    }

    private func expectContainsResult(in index: MeetingSearchIndex, query: String, meetingID: UUID) {
        let results = index.search(query, limit: 5)
        #expect(results.contains { $0.meetingID == meetingID })
    }
}
