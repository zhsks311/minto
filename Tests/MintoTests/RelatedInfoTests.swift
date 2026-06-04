import Testing
@testable import MintoCore
import Foundation

/// notion-search MCP 응답 파싱 테스트.
///
/// 실제 서버 응답 포맷은 라이브로 확인되지 않았으므로, 가정된 포맷과 폴백 경로를 모두 검증한다.
/// - 가정 A: JSON {"results":[{"title":"...", "url":"..."}]} 형태
/// - 가정 B: JSON 파싱 실패 시 notion.so URL 정규식 폴백
@Suite("NotionMCPService 검색 응답 파싱")
struct NotionMCPParseTests {

    // MARK: - JSON 포맷 파싱

    @Test("JSON 포맷 A: results 배열에서 title·url 추출")
    func parsesJSONResults() throws {
        let json = """
        {
          "results": [
            { "title": "회의 준비 문서", "url": "https://www.notion.so/abc" },
            { "title": "설계 리뷰", "url": "https://www.notion.so/def" }
          ]
        }
        """
        let docs = NotionMCPService.parseSearchResults(json, limit: 5)
        #expect(docs.count == 2)
        #expect(docs[0].source == .notion)
        #expect(docs[0].title == "회의 준비 문서")
        #expect(docs[0].url == "https://www.notion.so/abc")
        #expect(docs[1].title == "설계 리뷰")
    }

    @Test("JSON: url 없는 항목은 건너뛴다")
    func jsonSkipsResultsWithoutURL() throws {
        let json = """
        { "results": [ { "title": "제목만" }, { "title": "있음", "url": "https://www.notion.so/x" } ] }
        """
        let docs = NotionMCPService.parseSearchResults(json, limit: 5)
        #expect(docs.count == 1)
        #expect(docs[0].url == "https://www.notion.so/x")
    }

    @Test("JSON: title 없으면 (제목 없음)")
    func jsonFallbackTitle() throws {
        let json = """
        { "results": [ { "url": "https://www.notion.so/abc" } ] }
        """
        let docs = NotionMCPService.parseSearchResults(json, limit: 5)
        #expect(docs.count == 1)
        #expect(docs[0].title == "(제목 없음)")
    }

    @Test("JSON: limit 초과분은 잘린다")
    func jsonRespectsLimit() throws {
        let items = (0..<10).map { #"{"title":"페이지\#($0)","url":"https://www.notion.so/\#($0)"}"# }.joined(separator: ",")
        let docs = NotionMCPService.parseSearchResults("{\"results\":[\(items)]}", limit: 3)
        #expect(docs.count == 3)
    }

    // MARK: - URL 정규식 폴백

    @Test("폴백: 깨진 JSON에서 notion.so URL 추출")
    func regexFallbackFromBrokenJSON() throws {
        let text = "관련 문서: https://www.notion.so/Meeting-Notes-abc123\n참고: https://www.notion.so/Design-def456"
        let docs = NotionMCPService.parseSearchResults(text, limit: 5)
        #expect(docs.count == 2)
        #expect(docs[0].url == "https://www.notion.so/Meeting-Notes-abc123")
        #expect(docs[0].source == .notion)
    }

    @Test("폴백: URL 끝의 구두점은 제거된다")
    func regexFallbackTrimsTrailingPunctuation() throws {
        let text = "참고 문서: https://www.notion.so/Design-abc123. 그리고 (https://www.notion.so/Plan-def456)"
        let docs = NotionMCPService.parseSearchResults(text, limit: 5)
        #expect(docs.count == 2)
        #expect(docs[0].url == "https://www.notion.so/Design-abc123")
        #expect(docs[1].url == "https://www.notion.so/Plan-def456")
    }

    @Test("폴백: limit 제한 적용")
    func regexFallbackRespectsLimit() throws {
        let lines = (0..<10).map { "항목 https://www.notion.so/page-\($0)" }.joined(separator: "\n")
        let docs = NotionMCPService.parseSearchResults(lines, limit: 3)
        #expect(docs.count == 3)
    }

    // MARK: - 공통 엣지 케이스

    @Test("빈 입력 → 빈 배열")
    func emptyInputReturnsEmpty() throws {
        #expect(NotionMCPService.parseSearchResults("", limit: 5).isEmpty)
    }

    @Test("JSON이지만 results 없음 → 정규식 폴백 시도 후 빈 배열")
    func emptyResultsJSONReturnsEmpty() throws {
        #expect(NotionMCPService.parseSearchResults("{}", limit: 5).isEmpty)
        #expect(NotionMCPService.parseSearchResults("{\"results\":[]}", limit: 5).isEmpty)
    }

    @Test("notion.so URL이 없는 평문 → 빈 배열")
    func plainTextWithoutURLReturnsEmpty() throws {
        #expect(NotionMCPService.parseSearchResults("관련 문서가 없습니다.", limit: 5).isEmpty)
    }

    @Test("fetch 본문: 마크다운·URL 줄을 정리해 짧은 snippet 생성")
    func fetchedTextBecomesSnippet() throws {
        let text = """
        # 컬리 용어 모음집
        https://www.notion.so/abc
        - FBK는 Fulfillment by Kurly를 의미한다.
        [원문 링크](https://example.com)
        """
        let snippet = NotionMCPService.snippet(fromFetchedText: text)
        #expect(snippet == "컬리 용어 모음집 FBK는 Fulfillment by Kurly를 의미한다.")
    }

    @Test("fetch 본문: 빈 텍스트는 nil")
    func emptyFetchedTextHasNoSnippet() throws {
        #expect(NotionMCPService.snippet(fromFetchedText: " \n https://www.notion.so/x \n ") == nil)
    }

    @Test("fetch 본문: 긴 텍스트는 제한 길이로 자른다")
    func longFetchedTextIsTruncated() throws {
        let text = String(repeating: "가", count: 20)
        let snippet = NotionMCPService.snippet(fromFetchedText: text, maxLength: 5)
        #expect(snippet == "가가가가가...")
    }
}

@Suite("Confluence 검색 응답 파싱")
struct ConfluenceParseTests {

    @Test("_links.base + 상대 url → 절대 URL 조립")
    func buildsAbsoluteURL() throws {
        let json = """
        {
          "_links": { "base": "https://acme.atlassian.net/wiki" },
          "results": [
            {
              "content": { "title": "설계 문서" },
              "url": "/spaces/ENG/pages/123/Design",
              "excerpt": "이 문서는 @@@hl@@@설계@@@endhl@@@ 내용을 담는다"
            }
          ]
        }
        """
        let docs = ConfluenceService.parse(Data(json.utf8), fallbackBase: "https://fallback/wiki", limit: 5)
        #expect(docs.count == 1)
        #expect(docs[0].source == .confluence)
        #expect(docs[0].title == "설계 문서")
        #expect(docs[0].url == "https://acme.atlassian.net/wiki/spaces/ENG/pages/123/Design")
        #expect(docs[0].snippet == "이 문서는 설계 내용을 담는다")
    }

    @Test("_links.base 없으면 fallbackBase 사용")
    func usesFallbackBase() throws {
        let json = """
        { "results": [ { "content": { "title": "T" }, "url": "/x" } ] }
        """
        let docs = ConfluenceService.parse(Data(json.utf8), fallbackBase: "https://fb.atlassian.net/wiki", limit: 5)
        #expect(docs.count == 1)
        #expect(docs[0].url == "https://fb.atlassian.net/wiki/x")
    }

    @Test("상대 url이 / 없이 시작해도 안전하게 결합")
    func handlesRelativePathWithoutLeadingSlash() throws {
        let json = """
        { "results": [ { "content": { "title": "T" }, "url": "spaces/X/p" } ] }
        """
        let docs = ConfluenceService.parse(Data(json.utf8), fallbackBase: "https://fb.atlassian.net/wiki", limit: 5)
        #expect(docs[0].url == "https://fb.atlassian.net/wiki/spaces/X/p")
    }

    @Test("이미 절대 URL이면 그대로")
    func keepsAbsoluteURL() throws {
        let json = """
        { "results": [ { "content": { "title": "T" }, "url": "https://full.example/p" } ] }
        """
        let docs = ConfluenceService.parse(Data(json.utf8), fallbackBase: "https://fb/wiki", limit: 5)
        #expect(docs[0].url == "https://full.example/p")
    }

    @Test("url 없는 항목은 건너뛴다")
    func skipsResultsWithoutURL() throws {
        let json = """
        { "results": [ { "content": { "title": "T" } } ] }
        """
        #expect(ConfluenceService.parse(Data(json.utf8), fallbackBase: "https://fb/wiki", limit: 5).isEmpty)
    }

    @Test("content.title 없으면 result.title 폴백, 둘 다 없으면 (제목 없음)")
    func titleFallback() throws {
        let topLevel = """
        { "results": [ { "title": "상위제목", "url": "/a" } ] }
        """
        let none = """
        { "results": [ { "url": "/b" } ] }
        """
        #expect(ConfluenceService.parse(Data(topLevel.utf8), fallbackBase: "https://fb/wiki", limit: 5)[0].title == "상위제목")
        #expect(ConfluenceService.parse(Data(none.utf8), fallbackBase: "https://fb/wiki", limit: 5)[0].title == "(제목 없음)")
    }

    @Test("깨진 JSON → 빈 배열")
    func malformedReturnsEmpty() throws {
        #expect(ConfluenceService.parse(Data("oops".utf8), fallbackBase: "https://fb/wiki", limit: 5).isEmpty)
    }
}

@Suite("Confluence 자격·URL 정규화")
@MainActor
struct ConfluenceConfigTests {

    private func makeService() -> (ConfluenceService, UserDefaults) {
        let suite = "test.confluence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (ConfluenceService(defaults: defaults), defaults)
    }

    @Test("baseURL: 끝의 / 와 /wiki 제거")
    func normalizesBaseURL() {
        let (service, _) = makeService()
        service.setBaseURL("https://acme.atlassian.net/wiki/")
        #expect(service.baseURL == "https://acme.atlassian.net")

        service.setBaseURL("https://acme.atlassian.net/")
        #expect(service.baseURL == "https://acme.atlassian.net")

        service.setBaseURL("https://acme.atlassian.net")
        #expect(service.baseURL == "https://acme.atlassian.net")
    }

    @Test("baseURL: /wiki 이하 컨텍스트 경로 전체 제거")
    func stripsContextPath() {
        let (service, _) = makeService()
        service.setBaseURL("https://acme.atlassian.net/wiki/spaces/ENG")
        #expect(service.baseURL == "https://acme.atlassian.net")
    }

    @Test("빈 URL·email → nil")
    func emptyValuesAreNil() {
        let (service, _) = makeService()
        #expect(service.baseURL == nil)
        #expect(service.email == nil)
        service.setBaseURL("   ")
        service.setEmail("")
        #expect(service.baseURL == nil)
        #expect(service.email == nil)
    }
}

@Suite("Confluence CQL 이스케이프")
struct ConfluenceCQLTests {

    @Test("일반 검색어는 따옴표로 감싼다")
    func wrapsPlainQuery() {
        #expect(ConfluenceService.cqlQuery(for: "회의 안건") == "text ~ \"회의 안건\"")
    }

    @Test("내부 큰따옴표는 이스케이프(인젝션 차단)")
    func escapesQuotes() {
        // foo" AND creator = "admin  →  따옴표가 \" 로 이스케이프되어 전체가 리터럴
        let cql = ConfluenceService.cqlQuery(for: "foo\" AND creator = \"admin")
        #expect(cql == "text ~ \"foo\\\" AND creator = \\\"admin\"")
    }

    @Test("끝의 백슬래시가 닫는 따옴표를 깨뜨리지 않는다")
    func escapesTrailingBackslash() {
        let cql = ConfluenceService.cqlQuery(for: "foo\\")
        #expect(cql == "text ~ \"foo\\\\\"")
    }
}
