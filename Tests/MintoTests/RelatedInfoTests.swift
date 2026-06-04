import Testing
@testable import MintoCore
import Foundation

@Suite("Notion 검색 응답 파싱")
struct NotionParseTests {

    @Test("정상 응답 → 제목·URL 추출")
    func parsesValidResults() throws {
        let json = """
        {
          "results": [
            {
              "url": "https://www.notion.so/abc",
              "properties": {
                "Name": { "type": "title", "title": [
                  { "plain_text": "회의 " }, { "plain_text": "준비 문서" }
                ] }
              }
            }
          ]
        }
        """
        let docs = NotionService.parse(Data(json.utf8), limit: 5)
        #expect(docs.count == 1)
        #expect(docs[0].source == .notion)
        #expect(docs[0].title == "회의 준비 문서")
        #expect(docs[0].url == "https://www.notion.so/abc")
    }

    @Test("URL 없는 항목은 건너뛴다")
    func skipsResultsWithoutURL() throws {
        let json = """
        { "results": [ { "url": "", "properties": {} } ] }
        """
        let docs = NotionService.parse(Data(json.utf8), limit: 5)
        #expect(docs.isEmpty)
    }

    @Test("title 속성 없으면 (제목 없음)")
    func fallbackTitle() throws {
        let json = """
        { "results": [ { "url": "https://n.so/x", "properties": {} } ] }
        """
        let docs = NotionService.parse(Data(json.utf8), limit: 5)
        #expect(docs.count == 1)
        #expect(docs[0].title == "(제목 없음)")
    }

    @Test("limit 초과분은 잘린다")
    func respectsLimit() throws {
        let items = (0..<10).map { #"{ "url": "https://n.so/\#($0)", "properties": {} }"# }.joined(separator: ",")
        let docs = NotionService.parse(Data("{ \"results\": [\(items)] }".utf8), limit: 3)
        #expect(docs.count == 3)
    }

    @Test("깨진 JSON·빈 데이터 → 빈 배열")
    func malformedReturnsEmpty() throws {
        #expect(NotionService.parse(Data("not json".utf8), limit: 5).isEmpty)
        #expect(NotionService.parse(Data(), limit: 5).isEmpty)
        #expect(NotionService.parse(Data("{}".utf8), limit: 5).isEmpty)
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
