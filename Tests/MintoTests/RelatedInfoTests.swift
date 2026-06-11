import Testing
@testable import MintoCore
import Foundation
import MCP

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

    @Test("본문 응답 HTML을 회의 참고용 평문으로 정리한다")
    func parsesContentBodyText() throws {
        let json = """
        {
          "body": {
            "storage": {
              "value": "<h1>검색 고도화</h1><p>Confluence&nbsp;<strong>문서</strong>를 참고한다.</p><ul><li>SKU&amp;상품 용어</li></ul>"
            }
          }
        }
        """

        let text = ConfluenceService.parseContentBodyText(Data(json.utf8))

        #expect(text == "검색 고도화\nConfluence 문서를 참고한다.\n- SKU&상품 용어")
    }

    @Test("조회 문서를 프롬프트 참고자료 블록으로 만든다")
    func buildsContextBlock() throws {
        let docs = [
            ConfluenceService.ContextDocument(
                title: "검색 설계",
                text: "동의어와 도메인 용어를 검색 문맥에 반영한다.",
                url: "https://acme.atlassian.net/wiki/spaces/ENG/pages/1"
            )
        ]

        let block = ConfluenceService.contextBlock(from: docs)

        #expect(block.contains("[Confluence 참고 문서]"))
        #expect(block.contains("검색 설계"))
        #expect(block.contains("동의어와 도메인 용어"))
    }
}

@Suite("Confluence 내보내기 변환")
struct ConfluenceExportTests {

    @Test("공간 키 조회 응답에서 space id를 찾는다")
    func parsesSpaceID() {
        let json = """
        {
          "results": [
            { "id": "12345", "key": "ENG", "name": "Engineering" }
          ]
        }
        """

        #expect(ConfluenceService.parseSpaceID(Data(json.utf8), matchingKey: "eng") == "12345")
        #expect(ConfluenceService.parseSpaceID(Data(json.utf8), matchingKey: "HR") == nil)
        #expect(ConfluenceService.parseSpaceID(Data("{\"results\":[]}".utf8), matchingKey: "ENG") == nil)
    }

    @Test("Markdown을 Confluence storage HTML로 변환한다")
    func convertsMarkdownToStorageHTML() {
        let markdown = """
        # 회의록

        ## 결정사항
        - `00:12` **Liquibase** 사용
        - [ ] API token 확인

        전사 <원문> & 문맥
        """

        let html = ConfluenceService.storageHTML(fromMarkdown: markdown)

        #expect(html.contains("<h1>회의록</h1>"))
        #expect(html.contains("<h2>결정사항</h2>"))
        #expect(html.contains("<li><code>00:12</code> <strong>Liquibase</strong> 사용</li>"))
        #expect(html.contains("<li>[ ] API token 확인</li>"))
        #expect(html.contains("<p>전사 &lt;원문&gt; &amp; 문맥</p>"))
    }

    @Test("v2 페이지 생성 payload는 spaceId와 optional parentId를 포함한다")
    func createsV2PagePayload() throws {
        let data = try ConfluenceService.createPagePayload(
            title: "회의록",
            markdown: "# 제목",
            spaceID: "98765",
            parentID: " 54321 "
        )
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try #require(json["body"] as? [String: Any])

        #expect(json["status"] as? String == "current")
        #expect(json["title"] as? String == "회의록")
        #expect(json["spaceId"] as? String == "98765")
        #expect(json["parentId"] as? String == "54321")
        #expect(body["representation"] as? String == "storage")
        #expect((body["value"] as? String)?.contains("<h1>제목</h1>") == true)
    }

    @Test("부모 페이지 ID가 비어 있으면 payload에서 제외한다")
    func omitsBlankParentID() throws {
        let data = try ConfluenceService.createPagePayload(
            title: "회의록",
            markdown: "# 제목",
            spaceID: "98765",
            parentID: "   "
        )
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["parentId"] == nil)
    }

    @Test("생성 응답에서 열 수 있는 URL을 조립한다")
    func parsesPublishedPageURL() throws {
        let json = """
        {
          "id": "10001",
          "title": "회의록",
          "_links": {
            "base": "https://acme.atlassian.net/wiki",
            "webui": "/spaces/ENG/pages/10001"
          }
        }
        """

        let page = try #require(ConfluenceService.parsePublishedPage(Data(json.utf8), fallbackBase: "https://fallback/wiki"))

        #expect(page.id == "10001")
        #expect(page.title == "회의록")
        #expect(page.url == "https://acme.atlassian.net/wiki/spaces/ENG/pages/10001")
    }

    @Test("Confluence Cloud URL은 https atlassian.net만 허용한다")
    func validatesAllowedCloudBaseURL() {
        #expect(ConfluenceService.isAllowedCloudBaseURL("https://acme.atlassian.net"))
        #expect(ConfluenceService.isAllowedCloudBaseURL("https://team-prod.atlassian.net/"))
        #expect(!ConfluenceService.isAllowedCloudBaseURL("http://acme.atlassian.net"))
        #expect(!ConfluenceService.isAllowedCloudBaseURL("https://evil.example.com"))
        #expect(!ConfluenceService.isAllowedCloudBaseURL("https://atlassian.net"))
        #expect(!ConfluenceService.isAllowedCloudBaseURL("https://acme.atlassian.net.evil.example"))
        #expect(!ConfluenceService.isAllowedCloudBaseURL("https://acme.atlassian.net/wiki"))
    }
}

@Suite("Confluence 내보내기 재연결 상태")
@MainActor
struct ConfluenceExportReconnectTests {

    @Test("공간 조회 401은 재연결 필요 상태로 남긴다")
    func unauthorizedSpaceLookupMarksReconnectRequired() async {
        let httpClient = StubConfluenceHTTPClient(responses: [
            .init(statusCode: 401, data: Data("unauthorized".utf8))
        ])
        let tokenStorage = StubConfluenceTokenStorageBackend(loadData: Data("api-token".utf8), existsResult: true)
        let service = makeConfiguredConfluenceService(httpClient: httpClient, tokenStorage: tokenStorage)

        #expect(service.connectionState == .connected)

        await #expect(throws: ConfluenceService.ExportError.unauthorized) {
            _ = try await service.publishPage(title: "회의록", markdown: "# 회의록", spaceKey: "ENG")
        }

        #expect(service.connectionState == .needsReconnect)
        #expect(!service.isConfigured)
        #expect(tokenStorage.loadCallCount == 1)
        #expect(httpClient.requests.count == 1)
        #expect(httpClient.requests[0].httpMethod == "GET")
        #expect(httpClient.requests[0].url?.path == "/wiki/api/v2/spaces")
    }

    @Test("페이지 생성 401은 재연결 필요 상태로 남긴다")
    func unauthorizedPageCreateMarksReconnectRequired() async {
        let spaceResponse = """
        {
          "results": [
            { "id": "12345", "key": "ENG", "name": "Engineering" }
          ]
        }
        """
        let httpClient = StubConfluenceHTTPClient(responses: [
            .init(statusCode: 200, data: Data(spaceResponse.utf8)),
            .init(statusCode: 401, data: Data("unauthorized".utf8))
        ])
        let tokenStorage = StubConfluenceTokenStorageBackend(loadData: Data("api-token".utf8), existsResult: true)
        let service = makeConfiguredConfluenceService(httpClient: httpClient, tokenStorage: tokenStorage)

        #expect(service.connectionState == .connected)

        await #expect(throws: ConfluenceService.ExportError.unauthorized) {
            _ = try await service.publishPage(title: "회의록", markdown: "# 회의록", spaceKey: "ENG")
        }

        #expect(service.connectionState == .needsReconnect)
        #expect(!service.isConfigured)
        #expect(tokenStorage.loadCallCount == 1)
        #expect(httpClient.requests.count == 2)
        #expect(httpClient.requests[0].httpMethod == "GET")
        #expect(httpClient.requests[1].httpMethod == "POST")
        #expect(httpClient.requests[1].url?.path == "/wiki/api/v2/pages")
    }

    private func makeConfiguredConfluenceService(
        httpClient: StubConfluenceHTTPClient,
        tokenStorage: StubConfluenceTokenStorageBackend
    ) -> ConfluenceService {
        let defaults = InMemoryUserDefaults()
        let service = ConfluenceService(
            httpClient: httpClient,
            defaults: defaults,
            tokenStorage: tokenStorage
        )
        service.setBaseURL("https://acme.atlassian.net")
        service.setEmail("user@example.com")
        return service
    }
}

@Suite("Confluence 자격·URL 정규화")
@MainActor
struct ConfluenceConfigTests {

    private func makeService() -> (ConfluenceService, UserDefaults) {
        let defaults = InMemoryUserDefaults()
        return (
            ConfluenceService(
                httpClient: StubConfluenceHTTPClient(),
                defaults: defaults,
                tokenStorage: StubConfluenceTokenStorageBackend()
            ),
            defaults
        )
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

@Suite("연동 token 재연결 상태")
@MainActor
struct IntegrationReconnectStateTests {

    @Test("OAuth token decode 실패는 원문 재조회 없이 재연결 필요로 캐시된다")
    func oauthTokenDecodeFailureIsCachedAsReconnectRequired() {
        let storageBackend = StubOAuthTokenStorageBackend(loadData: Data("not-json".utf8), existsResult: true)
        let storage = KeychainTokenStorage(keychainKey: "test-notion", storage: storageBackend)

        #expect(storage.hasToken())
        #expect(storageBackend.loadCallCount == 0)

        #expect(storage.load() == nil)
        #expect(storage.requiresReconnect)
        #expect(!storage.hasToken())
        #expect(storageBackend.loadCallCount == 1)

        #expect(storage.load() == nil)
        #expect(storageBackend.loadCallCount == 1)
    }

    @Test("Notion OAuth 인증 실패는 다시 연결 필요 상태로 남긴다")
    func notionAuthorizationFailureMarksReconnectRequired() {
        let storageBackend = StubOAuthTokenStorageBackend(loadData: nil, existsResult: true)
        let tokenStorage = KeychainTokenStorage(keychainKey: "test-notion", storage: storageBackend)
        let service = NotionMCPService(tokenStorage: tokenStorage)

        #expect(service.connectionState == .connected)

        service.handleConnectionFailure(MCPError.internalError("Authorization flow failed: Token request failed with status 401"))

        #expect(service.connectionState == .needsReconnect)
        #expect(!service.isConfigured)
    }

    @Test("Notion 상태 조회는 token 원문을 읽지 않는다")
    func notionStatusChecksDoNotLoadTokenPayload() {
        let storageBackend = StubOAuthTokenStorageBackend(loadData: Data("stored-token".utf8), existsResult: true)
        let tokenStorage = KeychainTokenStorage(keychainKey: "test-notion-status", storage: storageBackend)
        let service = NotionMCPService(tokenStorage: tokenStorage)

        #expect(service.connectionState == .connected)
        #expect(service.isConnected)
        #expect(service.isConfigured)
        service.refreshConnectionStateFromStorage()
        #expect(service.connectionState == .connected)
        #expect(storageBackend.loadCallCount == 0)
    }

    @Test("Confluence 상태 조회는 token 원문을 읽지 않는다")
    func confluenceStatusChecksDoNotLoadTokenPayload() {
        let tokenStorage = StubConfluenceTokenStorageBackend(loadData: Data("api-token".utf8), existsResult: true)
        let service = makeConfiguredConfluenceService(tokenStorage: tokenStorage)

        #expect(service.connectionState == .connected)
        #expect(service.isConfigured)
        #expect(service.canDisconnect)
        #expect(service.connectionState == .connected)
        #expect(tokenStorage.loadCallCount == 0)
    }

    @Test("Confluence 연동 해제는 token과 URL/email을 함께 지운다")
    func confluenceDisconnectClearsTokenAndMetadata() {
        let defaults = InMemoryUserDefaults()
        let tokenStorage = StubConfluenceTokenStorageBackend(loadData: Data("api-token".utf8), existsResult: true)
        let service = ConfluenceService(
            httpClient: StubConfluenceHTTPClient(),
            defaults: defaults,
            tokenStorage: tokenStorage
        )
        service.setBaseURL("https://acme.atlassian.net/wiki")
        service.setEmail("user@example.com")

        #expect(service.connectionState == .connected)
        #expect(tokenStorage.exists(account: "confluence"))

        service.disconnect()

        #expect(service.connectionState == .disconnected)
        #expect(!service.canDisconnect)
        #expect(!tokenStorage.exists(account: "confluence"))
        #expect(defaults.string(forKey: ConfluenceService.baseURLKey) == nil)
        #expect(defaults.string(forKey: ConfluenceService.emailKey) == nil)
    }

    @Test("Confluence token decode 실패는 실제 사용 후 재연결 필요 상태로 남긴다")
    func confluenceInvalidStoredTokenMarksReconnectAfterUse() async {
        let tokenStorage = StubConfluenceTokenStorageBackend(loadData: Data([0xff]), existsResult: true)
        let service = makeConfiguredConfluenceService(tokenStorage: tokenStorage)

        #expect(service.connectionState == .connected)
        #expect(tokenStorage.loadCallCount == 0)

        let docs = await service.search("회의 안건")

        #expect(docs.isEmpty)
        #expect(service.connectionState == .needsReconnect)
        #expect(!service.isConfigured)
        #expect(tokenStorage.loadCallCount == 1)

        _ = await service.search("다시 조회")
        #expect(tokenStorage.loadCallCount == 1)
    }

    @Test("Confluence 401 응답은 token 원문 없이 재연결 필요 상태를 남긴다")
    func confluenceUnauthorizedSearchMarksReconnectRequired() async {
        let httpClient = StubConfluenceHTTPClient(responses: [
            .init(statusCode: 401, data: Data("unauthorized".utf8))
        ])
        let tokenStorage = StubConfluenceTokenStorageBackend(loadData: Data("api-token".utf8), existsResult: true)
        let service = makeConfiguredConfluenceService(httpClient: httpClient, tokenStorage: tokenStorage)

        #expect(service.connectionState == .connected)

        let docs = await service.search("회의 안건")

        #expect(docs.isEmpty)
        #expect(service.connectionState == .needsReconnect)
        #expect(!service.isConfigured)
        #expect(tokenStorage.loadCallCount == 1)
        #expect(httpClient.requests.count == 1)
        #expect(httpClient.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    }

    @Test("관련 문서 검색은 Confluence 인증 실패를 재연결 안내로 표시한다")
    func relatedInfoSearchShowsConfluenceReconnectMessage() async {
        let httpClient = StubConfluenceHTTPClient(responses: [
            .init(statusCode: 401, data: Data("unauthorized".utf8))
        ])
        let tokenStorage = StubConfluenceTokenStorageBackend(loadData: Data("api-token".utf8), existsResult: true)
        let confluence = makeConfiguredConfluenceService(httpClient: httpClient, tokenStorage: tokenStorage)
        let notionStorage = KeychainTokenStorage(
            keychainKey: "test-notion-related-info",
            storage: StubOAuthTokenStorageBackend(loadData: nil, existsResult: false)
        )
        let relatedInfo = RelatedInfoService(
            notionMCP: NotionMCPService(tokenStorage: notionStorage),
            confluence: confluence
        )

        await relatedInfo.search(query: "회의 안건")

        #expect(relatedInfo.results.isEmpty)
        #expect(relatedInfo.statusMessage == "Confluence 다시 연결이 필요해요. 설정에서 연결 정보를 갱신하세요.")
        #expect(confluence.connectionState == .needsReconnect)
        #expect(httpClient.requests.count == 1)
    }

    @Test("관련 문서 검색은 Notion 재연결 필요 상태를 연결 안내로 표시한다")
    func relatedInfoSearchShowsNotionReconnectMessage() async {
        let tokenStorage = KeychainTokenStorage(
            keychainKey: "test-notion-related-info",
            storage: StubOAuthTokenStorageBackend(loadData: nil, existsResult: true)
        )
        let notion = NotionMCPService(tokenStorage: tokenStorage)
        notion.handleConnectionFailure(MCPError.internalError("Authorization flow failed: Token request failed with status 401"))
        let confluence = makeConfiguredConfluenceService(tokenStorage: StubConfluenceTokenStorageBackend())
        let relatedInfo = RelatedInfoService(notionMCP: notion, confluence: confluence)

        #expect(relatedInfo.isAnyConfigured)

        await relatedInfo.search(query: "회의 안건")

        #expect(relatedInfo.results.isEmpty)
        #expect(relatedInfo.statusMessage == "Notion 다시 연결이 필요해요. 설정에서 연결 정보를 갱신하세요.")
    }

    private func makeConfiguredConfluenceService(
        httpClient: StubConfluenceHTTPClient = StubConfluenceHTTPClient(),
        tokenStorage: StubConfluenceTokenStorageBackend
    ) -> ConfluenceService {
        let defaults = InMemoryUserDefaults()
        let service = ConfluenceService(
            httpClient: httpClient,
            defaults: defaults,
            tokenStorage: tokenStorage
        )
        service.setBaseURL("https://acme.atlassian.net")
        service.setEmail("user@example.com")
        return service
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

private final class StubOAuthTokenStorageBackend: OAuthTokenStorageBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var existsResult: Bool?
    private var _loadCallCount = 0

    init(loadData: Data?, existsResult: Bool? = nil) {
        self.data = loadData
        self.existsResult = existsResult
    }

    var loadCallCount: Int {
        lock.withLock { _loadCallCount }
    }

    func exists(key: String) -> Bool {
        lock.withLock { existsResult ?? (data != nil) }
    }

    func load(key: String) -> Data? {
        lock.withLock {
            _loadCallCount += 1
            return data
        }
    }

    func save(key: String, data: Data) {
        lock.withLock {
            self.data = data
            existsResult = true
        }
    }

    func delete(key: String) {
        lock.withLock {
            data = nil
            existsResult = false
        }
    }
}

private final class StubConfluenceTokenStorageBackend: ConfluenceTokenStorageBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var existsResult: Bool?
    private var _loadCallCount = 0

    init(loadData: Data? = nil, existsResult: Bool? = nil) {
        self.data = loadData
        self.existsResult = existsResult
    }

    var loadCallCount: Int {
        lock.withLock { _loadCallCount }
    }

    func exists(account: String) -> Bool {
        lock.withLock { existsResult ?? (data != nil) }
    }

    func load(account: String) -> Data? {
        lock.withLock {
            _loadCallCount += 1
            return data
        }
    }

    func save(account: String, data: Data) {
        lock.withLock {
            self.data = data
            existsResult = true
        }
    }

    func delete(account: String) {
        lock.withLock {
            data = nil
            existsResult = false
        }
    }
}

private final class StubConfluenceHTTPClient: ConfluenceHTTPClient, @unchecked Sendable {
    struct Response: Sendable {
        let statusCode: Int
        let data: Data
    }

    private let lock = NSLock()
    private var responses: [Response]
    private var _requests: [URLRequest] = []

    init(responses: [Response] = []) {
        self.responses = responses
    }

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = lock.withLock { () -> Response in
            _requests.append(request)
            if responses.isEmpty {
                return Response(statusCode: 200, data: Data(#"{"results":[]}"#.utf8))
            }
            return responses.removeFirst()
        }
        let url = request.url ?? URL(string: "https://acme.atlassian.net")!
        let http = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response.data, http)
    }
}
