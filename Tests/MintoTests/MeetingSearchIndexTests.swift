import Foundation
import Testing
@testable import MintoCore

@Suite("MeetingSearchIndex")
struct MeetingSearchIndexTests {
    private func sampleRecord(
        transcriptID: UUID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        document: String? = nil
    ) -> MeetingRecord {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return MeetingRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "db 스키마 형상 관리 툴 적용과 기록 방식",
            startedAt: startedAt,
            durationSeconds: 245,
            topic: "Liquibase와 Flyway 비교",
            summary: MeetingSummary(
                title: "db 스키마 형상 관리",
                leadQuestion: "db 스키마 변경을 어떻게 기록할까?",
                leadAnswer: "flyway와 liquibase로 SQL 변경 이력을 관리하는 방식을 논의했다.",
                sections: [
                    .init(
                        title: "1. flyway를 통한 스키마 변경 적용",
                        time: "01:02",
                        points: [
                            .init(text: "버전 기반 SQL 변경 적용", subPoints: [
                                "price 컬럼을 추가하려면 SQL 파일을 V2로 추가한다.",
                                "히스토리 테이블에 적용 기록이 남는다."
                            ])
                        ]
                    ),
                    .init(
                        title: "2. liquibase 방식과 xml 관리",
                        time: "01:30",
                        points: [
                            .init(text: "DDL을 XML 파일로 관리한다.", subPoints: [
                                "change-log-master.xml include 문법을 쓴다."
                            ])
                        ]
                    )
                ],
                keywords: ["flyway", "liquibase", "db", "마이그레이션"],
                decisions: [.init(text: "DB 형상 관리 자체는 중요하다.", time: "03:22")],
                actionItems: [.init(task: "팀 적용 범위를 다시 검토한다.", owner: "민토", due: "다음 회의", time: "03:45")],
                openQuestions: [.init(text: "엔티티 변경을 SQL 파일로 다시 만드는 과정이 번거로운가?", time: "02:32")]
            ),
            document: document,
            transcript: [
                Segment(
                    id: transcriptID,
                    text: "컬럼 추가와 인덱스 추가 이력을 추적해야 합니다.",
                    timestamp: startedAt.addingTimeInterval(132),
                    duration: 8
                )
            ]
        )
    }

    @Test("회의 한 건을 검색 가능한 chunk로 분리한다")
    func buildsChunks() {
        let chunks = MeetingSearchIndex.chunks(for: sampleRecord())

        #expect(chunks.contains { $0.kind == .title })
        #expect(chunks.contains { $0.kind == .topic })
        #expect(chunks.contains { $0.kind == .summary })
        #expect(chunks.contains { $0.kind == .section && $0.time == "01:02" })
        #expect(chunks.contains { $0.kind == .decision && $0.time == "03:22" })
        #expect(chunks.contains { $0.kind == .actionItem && $0.text.contains("민토") })
        #expect(chunks.contains { $0.kind == .openQuestion })
        #expect(chunks.contains { $0.kind == .transcript && $0.time == "02:12" })
        #expect(chunks.allSatisfy { $0.chunkingVersion == MeetingSearchIndex.chunkingVersion })
        #expect(chunks.contains { $0.sourcePath == "summary.sections[0]" })
        #expect(chunks.contains { $0.sourcePath.hasPrefix("transcript[") })
    }

    @Test("회의 자료가 있으면 document chunk를 만든다")
    func buildsDocumentChunks() {
        let chunks = MeetingSearchIndex.chunks(for: sampleRecord(document: "첨부 자료에만 있는 보안 검토 내용"))

        #expect(chunks.contains { $0.kind == .document })
    }

    @Test("회의 자료가 nil이거나 공백이면 document chunk를 만들지 않는다")
    func blankDocumentBuildsNoDocumentChunks() {
        let nilChunks = MeetingSearchIndex.chunks(for: sampleRecord())
            .filter { $0.kind == .document }
        let blankChunks = MeetingSearchIndex.chunks(for: sampleRecord(document: " \n\n\t "))
            .filter { $0.kind == .document }

        #expect(nilChunks.isEmpty)
        #expect(blankChunks.isEmpty)
    }

    @Test("회의 자료는 빈 줄 기준 문단 단위로 chunk를 만든다")
    func documentSplitsIntoParagraphChunks() {
        let chunks = MeetingSearchIndex.chunks(for: sampleRecord(document: "첫 문단 자료\n\n둘째 문단 자료"))
            .filter { $0.kind == .document }

        #expect(chunks.count == 2)
        #expect(chunks.map(\.sourcePath) == ["document[0]", "document[1]"])
        #expect(chunks.map(\.text) == ["첫 문단 자료", "둘째 문단 자료"])
    }

    @Test("CRLF 단일 줄바꿈은 같은 문단으로 묶고, CRLF 빈 줄에서만 문단을 나눈다")
    func documentHandlesCRLFLineEndings() {
        // "\r\n" 단일 줄바꿈으로 이어진 줄은 한 문단, "\r\n\r\n" 빈 줄에서만 분할돼야 한다.
        let chunks = MeetingSearchIndex.chunks(for: sampleRecord(document: "첫 줄\r\n둘째 줄\r\n\r\n다음 문단"))
            .filter { $0.kind == .document }

        #expect(chunks.count == 2)
        #expect(chunks.map(\.text) == ["첫 줄\n둘째 줄", "다음 문단"])
    }

    @Test("800자를 넘는 단일 회의 자료 문단은 연속 sourcePath의 작은 chunk로 나눈다")
    func longDocumentParagraphSplitsIntoCappedChunks() {
        let document = String(repeating: "가", count: 1_650)
        let chunks = MeetingSearchIndex.chunks(for: sampleRecord(document: document))
            .filter { $0.kind == .document }

        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.text.count <= 800 })
        #expect(chunks.map(\.sourcePath) == chunks.indices.map { "document[\($0)]" })
    }

    @Test("회의 자료 길이 상한은 가능한 경우 단어 중간이 아니라 공백 경계에서 나눈다")
    func longDocumentParagraphSplitsAtWhitespaceBoundary() {
        let words = (0..<160).map { "word\($0)" }
        let document = words.joined(separator: " ")
        let chunks = MeetingSearchIndex.chunks(for: sampleRecord(document: document))
            .filter { $0.kind == .document }

        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.text.count <= 800 })
        // 공백 개수에 의존하지 않고 "단어가 중간에 쪼개지지 않고 순서가 보존되는지"를 직접 검증한다.
        let rejoinedWords = chunks.flatMap { $0.text.split(separator: " ") }
        #expect(rejoinedWords == words.map { Substring($0) })
    }

    @Test("800자 미만 회의 자료 문단은 기존처럼 단일 document chunk를 유지한다")
    func shortDocumentParagraphKeepsSingleChunk() throws {
        let document = "짧은 회의 자료 문단은 쪼개지 않아요."
        let chunks = MeetingSearchIndex.chunks(for: sampleRecord(document: document))
            .filter { $0.kind == .document }
        let chunk = try #require(chunks.first)

        #expect(chunks.count == 1)
        #expect(chunk.sourcePath == "document[0]")
        #expect(chunk.text == document)
    }

    @Test("같은 회의를 다시 index해도 chunk id와 checksum이 안정적이다")
    func chunksAreDeterministic() {
        let first = MeetingSearchIndex.chunks(for: sampleRecord())
        let second = MeetingSearchIndex.chunks(for: sampleRecord())

        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.checksum) == second.map(\.checksum))
    }

    @Test("전사 segment UUID가 달라도 같은 내용과 시간은 같은 chunk id를 만든다")
    func transcriptChunkDoesNotDependOnSegmentID() {
        let first = MeetingSearchIndex.chunks(for: sampleRecord(transcriptID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!))
        let second = MeetingSearchIndex.chunks(for: sampleRecord(transcriptID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!))

        let firstTranscript = first.first { $0.kind == .transcript }
        let secondTranscript = second.first { $0.kind == .transcript }
        #expect(firstTranscript?.id == secondTranscript?.id)
        #expect(firstTranscript?.sourcePath == "transcript[0]")
    }

    @Test("회의 검색은 제목보다 세부 chunk가 맞아도 회의를 찾는다")
    func searchFindsMatchingChunks() {
        let record = sampleRecord()
        let index = MeetingSearchIndex(records: [record])

        let results = index.search("change-log-master include", limit: 5)

        #expect(results.first?.meetingID == record.id)
        #expect(results.contains { $0.chunk.kind == .section })
        #expect(results.first?.preview.contains("change-log-master.xml") == true)
    }

    @Test("회의 자료에만 있는 단어로 검색하면 해당 document chunk를 반환한다")
    func searchFindsDocumentOnlyTerm() {
        let record = sampleRecord(document: "외부 첨부 문서에 doconlytoken 항목이 있다.")
        let index = MeetingSearchIndex(records: [record])

        let results = index.search("doconlytoken", limit: 5)

        #expect(results.contains { $0.meetingID == record.id && $0.chunk.kind == .document })
    }

    @Test("빈 검색어는 결과를 반환하지 않는다")
    func blankQueryReturnsEmpty() {
        let index = MeetingSearchIndex(records: [sampleRecord()])

        #expect(index.search("  ").isEmpty)
    }

    @Test("DB 스키마 형상 관리 질의는 관련 회의를 반환한다")
    func dbSchemaQueryFindsMeeting() {
        let record = sampleRecord()
        let other = MeetingRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "제품 리뷰",
            startedAt: record.startedAt.addingTimeInterval(-100),
            durationSeconds: 60,
            summary: MeetingSummary(leadAnswer: "릴리즈 일정만 논의했다."),
            transcript: [Segment(text: "제품 화면을 확인했다.", timestamp: record.startedAt, duration: 3)]
        )
        let index = MeetingSearchIndex(records: [other, record])

        let results = index.search("db 스키마 형상 관리", limit: 5)

        #expect(results.first?.meetingID == record.id)
        #expect(results.first?.label == "제목")
    }

    @Test("제목과 전사가 모두 맞으면 제목 chunk가 대표 결과가 된다")
    func titleWinsOverTranscriptForSameMatch() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = MeetingRecord(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "예산 검토",
            startedAt: startedAt,
            durationSeconds: 30,
            transcript: [
                Segment(
                    id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                    text: "예산 검토",
                    timestamp: startedAt.addingTimeInterval(10),
                    duration: 3
                )
            ]
        )

        let results = MeetingSearchIndex(records: [record]).search("예산 검토", limit: 5)

        #expect(results.first?.chunk.kind == .title)
        #expect(results.first?.label == "제목")
    }

    @Test("악센트 차이는 같은 검색어로 취급한다")
    func searchFoldsDiacritics() {
        let record = MeetingRecord(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            title: "Cafe 리뷰",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 20,
            summary: MeetingSummary(leadAnswer: "café 메뉴를 검토했다.")
        )

        let results = MeetingSearchIndex(records: [record]).search("cafe", limit: 5)

        #expect(results.contains { $0.chunk.kind == .summary })
    }
}

@Suite("MeetingSearchIndexStore 디스크 캐시")
struct MeetingSearchIndexStoreDiskCacheTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingSearchIndexStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleRecord(id: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: "테스트 회의",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 60,
            summary: MeetingSummary(leadAnswer: "요약")
        )
    }

    @Test("저장한 인덱스를 로드하면 동일한 chunk를 반환한다")
    func loadReturnsSavedIndex() throws {
        let dir = try tempDir()
        let indexStore = MeetingSearchIndexStore(directory: dir)
        let record = sampleRecord()
        let built = MeetingSearchIndex(records: [record])

        indexStore.save(built)
        let loaded = indexStore.load()

        #expect(loaded != nil)
        #expect(loaded?.chunks.map(\.id).sorted() == built.chunks.map(\.id).sorted())
    }

    @Test("저장된 인덱스의 meetingID 집합이 현재 meetings와 일치하면 정합 판정")
    func idSetMatchIndicatesCompatibility() throws {
        let dir = try tempDir()
        let indexStore = MeetingSearchIndexStore(directory: dir)
        let record = sampleRecord()
        indexStore.save(MeetingSearchIndex(records: [record]))

        let loaded = indexStore.load()
        let indexedIDs = Set(loaded?.chunks.map(\.meetingID) ?? [])
        let currentIDs = Set([record.id])

        #expect(indexedIDs == currentIDs)
    }

    @Test("회의 ID 집합이 달라지면 불일치 판정 — 재빌드 필요")
    func idSetMismatchIndicatesRebuildNeeded() throws {
        let dir = try tempDir()
        let indexStore = MeetingSearchIndexStore(directory: dir)
        let record = sampleRecord()
        indexStore.save(MeetingSearchIndex(records: [record]))

        let loaded = indexStore.load()
        let indexedIDs = Set(loaded?.chunks.map(\.meetingID) ?? [])
        // 회의가 한 건 추가된 상황
        let newID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let currentIDs: Set<UUID> = [record.id, newID]

        #expect(indexedIDs != currentIDs)
    }

    @Test("인덱스 파일이 없으면 load는 nil을 반환한다")
    func loadReturnsNilWhenNoFile() throws {
        let dir = try tempDir()
        let indexStore = MeetingSearchIndexStore(directory: dir)

        #expect(indexStore.load() == nil)
    }

    @Test("save 실패 후 invalidate를 호출하면 load가 nil을 반환한다")
    func invalidateAfterSaveFailureRemovesStaleIndex() throws {
        let dir = try tempDir()
        let indexStore = MeetingSearchIndexStore(directory: dir)
        let record = sampleRecord()

        // 정상 저장 → load 성공 확인
        indexStore.save(MeetingSearchIndex(records: [record]))
        #expect(indexStore.load() != nil)

        // invalidate → load가 nil 반환 (재빌드 경로로 진입)
        indexStore.invalidate()
        #expect(indexStore.load() == nil)
    }
}
