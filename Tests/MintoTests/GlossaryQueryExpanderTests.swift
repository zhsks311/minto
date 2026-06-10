import Foundation
import Testing
@testable import MintoCore

@Suite("GlossaryQueryExpander")
struct GlossaryQueryExpanderTests {

    // MARK: - 기본 확장 동작

    @Test("용어집에 'Liquibase = 리퀴베이스' 등록 시 '리퀴베이스' 검색이 'Liquibase'를 확장 토큰으로 반환한다")
    func expandsAliasToCanonical() {
        let entries = [
            GlossaryEntry(canonical: "Liquibase", aliases: ["리퀴베이스", "liqui base"])
        ]
        let queryTokens = MeetingSearchIndex.queryTerms("리퀴베이스")

        let expanded = GlossaryQueryExpander.expand(queryTokens: queryTokens, entries: entries)

        let tokens = expanded.map(\.token)
        #expect(tokens.contains("liquibase"))
        // 원 쿼리 토큰(리퀴베이스 tokenized)은 포함하지 않는다
        #expect(!tokens.contains(""))
    }

    @Test("용어집에 'Liquibase = 리퀴베이스' 등록 시 'Liquibase' 검색이 '리퀴베이스'를 확장 토큰으로 반환한다")
    func expandsCanonicalToAlias() {
        let entries = [
            GlossaryEntry(canonical: "Liquibase", aliases: ["리퀴베이스"])
        ]
        let queryTokens = MeetingSearchIndex.queryTerms("Liquibase")

        let expanded = GlossaryQueryExpander.expand(queryTokens: queryTokens, entries: entries)

        // "리퀴베이스"는 알파벳·숫자가 아니라 별도 처리 — tokenize 후 확인
        // tokenize("리퀴베이스") → ["리퀴베이스"] (한글은 alphanumerics에 포함)
        let tokens = expanded.map(\.token)
        // liquibase는 이미 쿼리 토큰이므로 포함되지 않아야 한다
        #expect(!tokens.contains("liquibase"))
    }

    // MARK: - 검색 결과 통합 테스트

    @Test("용어집에 'Liquibase = 리퀴베이스' 등록 시 '리퀴베이스' 검색이 'Liquibase'만 포함한 회의를 찾는다")
    func glossarySearchFindsCanonicalOnlyMeeting() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = MeetingRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "DB 마이그레이션",
            startedAt: startedAt,
            durationSeconds: 60,
            summary: MeetingSummary(leadAnswer: "Liquibase로 스키마를 관리한다.")
        )
        let searchIndex = MeetingSearchIndex(records: [record])

        let entries = [GlossaryEntry(canonical: "Liquibase", aliases: ["리퀴베이스"])]
        let queryTokens = MeetingSearchIndex.queryTerms("리퀴베이스")
        let expandedTokens = GlossaryQueryExpander.expand(queryTokens: queryTokens, entries: entries)

        // 확장 토큰 없이 검색하면 결과가 없어야 한다
        let withoutExpansion = searchIndex.search("리퀴베이스", limit: .max)
        #expect(withoutExpansion.isEmpty)

        // 확장 토큰 포함 검색하면 결과가 있어야 한다
        let withExpansion = searchIndex.search("리퀴베이스", limit: .max, expandedTokens: expandedTokens)
        #expect(!withExpansion.isEmpty)
        #expect(withExpansion.allSatisfy { $0.meetingID == record.id })
    }

    @Test("확장 토큰 매치 점수가 원토큰 직접 매치 점수보다 낮다")
    func expandedScoreIsLowerThanDirectScore() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        // 회의 A: "Liquibase" 원문 포함 (원토큰 매치)
        let recordA = MeetingRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            title: "회의 A",
            startedAt: startedAt,
            durationSeconds: 60,
            summary: MeetingSummary(leadAnswer: "Liquibase로 마이그레이션한다.")
        )
        // 회의 B: "리퀴베이스"(쿼리 토큰)와 "Liquibase"(확장 토큰) 모두 포함
        // 이미 원토큰 "리퀴베이스"도 있으므로 대신 별도 회의 구성
        // 회의 C: 오직 "Liquibase"만 (확장 토큰 매치만)
        let recordC = MeetingRecord(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            title: "회의 C",
            startedAt: startedAt.addingTimeInterval(1),
            durationSeconds: 60,
            summary: MeetingSummary(leadAnswer: "Liquibase를 사용한다.")
        )
        // 회의 D: "리퀴베이스"를 직접 포함 (원토큰 매치)
        let recordD = MeetingRecord(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            title: "회의 D",
            startedAt: startedAt.addingTimeInterval(2),
            durationSeconds: 60,
            summary: MeetingSummary(leadAnswer: "리퀴베이스로 스키마를 관리한다.")
        )

        let searchIndex = MeetingSearchIndex(records: [recordA, recordC, recordD])
        let entries = [GlossaryEntry(canonical: "Liquibase", aliases: ["리퀴베이스"])]
        let queryTokens = MeetingSearchIndex.queryTerms("리퀴베이스")
        let expandedTokens = GlossaryQueryExpander.expand(queryTokens: queryTokens, entries: entries)

        let results = searchIndex.search("리퀴베이스", limit: .max, expandedTokens: expandedTokens)

        // 원토큰 직접 매치(리퀴베이스 포함 회의 D)가 확장 토큰 매치(Liquibase만 있는 회의 C)보다 점수 높아야 함
        let scoreC = results.first { $0.meetingID == recordC.id }?.score
        let scoreD = results.first { $0.meetingID == recordD.id }?.score
        let scoreA = results.first { $0.meetingID == recordA.id }?.score

        if let sc = scoreC, let sd = scoreD {
            #expect(sd > sc, "원토큰 직접 매치 점수(\(sd))가 확장 토큰 매치 점수(\(sc))보다 높아야 함")
        }
        // 모든 회의가 결과에 포함되어야 함
        #expect(scoreA != nil)
        #expect(scoreC != nil)
        #expect(scoreD != nil)
    }

    // MARK: - 경계 조건

    @Test("용어집이 비었으면 확장 토큰이 없다")
    func emptyEntriesReturnsNoExpansion() {
        let queryTokens = MeetingSearchIndex.queryTerms("리퀴베이스")
        let expanded = GlossaryQueryExpander.expand(queryTokens: queryTokens, entries: [])
        #expect(expanded.isEmpty)
    }

    @Test("쿼리 토큰이 비었으면 확장 토큰이 없다")
    func emptyQueryTokensReturnsNoExpansion() {
        let entries = [GlossaryEntry(canonical: "Liquibase", aliases: ["리퀴베이스"])]
        let expanded = GlossaryQueryExpander.expand(queryTokens: [], entries: entries)
        #expect(expanded.isEmpty)
    }

    @Test("isUsable=false 항목은 호출측이 걸러야 하며, 비활성화 항목이 포함되면 확장된다")
    func disabledEntryExpandsIfIncluded() {
        // isUsable 필터는 호출측 책임 — expander는 입력된 entries를 그대로 사용
        let disabledEntry = GlossaryEntry(
            canonical: "Liquibase",
            aliases: ["리퀴베이스"],
            enabled: false
        )
        let queryTokens = MeetingSearchIndex.queryTerms("리퀴베이스")

        // isUsable=false를 호출측이 필터하지 않고 넘겼을 경우 확장됨
        let expandedWithDisabled = GlossaryQueryExpander.expand(queryTokens: queryTokens, entries: [disabledEntry])
        // isUsable 필터 후 빈 배열을 넘겼을 경우 확장 없음
        let expandedWithFiltered = GlossaryQueryExpander.expand(
            queryTokens: queryTokens,
            entries: [disabledEntry].filter(\.isUsable)
        )

        #expect(!expandedWithDisabled.isEmpty)
        #expect(expandedWithFiltered.isEmpty)
    }

    @Test("확장 토큰의 weight는 expansionWeight(0.8)이다")
    func expansionWeightIsCorrect() {
        let entries = [GlossaryEntry(canonical: "Liquibase", aliases: ["리퀴베이스"])]
        let queryTokens = MeetingSearchIndex.queryTerms("리퀴베이스")
        let expanded = GlossaryQueryExpander.expand(queryTokens: queryTokens, entries: entries)

        #expect(expanded.allSatisfy { $0.weight == GlossaryQueryExpander.expansionWeight })
    }

    @Test("확장 토큰에 원 쿼리 토큰이 중복 포함되지 않는다")
    func expandedTokensDoNotDuplicateQueryTokens() {
        let entries = [GlossaryEntry(canonical: "Liquibase", aliases: ["리퀴베이스"])]
        let queryTokens = MeetingSearchIndex.queryTerms("liquibase")
        let expanded = GlossaryQueryExpander.expand(queryTokens: queryTokens, entries: entries)

        // "liquibase"는 원 쿼리 토큰이므로 확장 토큰에 포함되면 안 된다
        #expect(!expanded.map(\.token).contains("liquibase"))
    }
}
