import Foundation
import MCP

/// Notion 공식 MCP 서버(https://mcp.notion.com/mcp)에 OAuth 2.1로 연결해
/// 전사 키워드로 Notion 페이지를 검색하는 서비스.
///
/// 인증: OAuth DCR + PKCE + 공개클라이언트(none). ASWebAuthenticationSession으로 브라우저를 띄우고,
/// 발급된 토큰은 Keychain에 영속 저장돼 재실행 시 재인증이 불필요하다.
@MainActor
public final class NotionMCPService: ObservableObject {
    public static let shared = NotionMCPService()

    // MARK: - 상수

    private static let endpoint = URL(string: "https://mcp.notion.com/mcp")!
    private static let redirectURI = URL(string: "minto2://oauth/callback")!
    private static let keychainKey = "notion-mcp"
    private static let searchToolName = "notion-search"

    // MARK: - 상태

    private let tokenStorage = KeychainTokenStorage(keychainKey: NotionMCPService.keychainKey)

    /// 저장된 토큰 유무로 연결 상태를 초기화한다.
    @Published public private(set) var isConnected: Bool

    public var isConfigured: Bool { isConnected }

    // MARK: - 초기화

    private init() {
        self.isConnected = false
        self.isConnected = (tokenStorage.load() != nil)
    }

    // MARK: - Client 생성

    /// OAuthConfiguration + OAuthAuthorizer + HTTPClientTransport + Client를 조립해 연결된 Client를 반환한다.
    ///
    /// - Parameter interactive: true면 브라우저 인증(delegate 제공)을 허용한다(연결 버튼 경로).
    ///   false면 delegate 없이 — 토큰/갱신만으로 붙고, 대화형 인증이 필요하면 조용히 실패한다.
    ///   검색 중 토큰 만료·갱신 실패 시 브라우저가 무인으로 뜨는 것을 막는다.
    private func makeConnectedClient(interactive: Bool) async throws -> Client {
        let config = OAuthConfiguration(
            grantType: .authorizationCode,
            authentication: .none(clientID: ""),
            authorizationRedirectURI: Self.redirectURI,
            clientName: "Minto2",
            authorizationDelegate: interactive ? OAuthBrowserDelegate() : nil
        )
        let authorizer = OAuthAuthorizer(configuration: config, tokenStorage: tokenStorage)
        let transport = HTTPClientTransport(endpoint: Self.endpoint, authorizer: authorizer)
        let client = Client(name: "Minto2", version: "1.0")
        try await client.connect(transport: transport)
        return client
    }

    // MARK: - 공개 API

    /// OAuth 인증 흐름을 실행하고 연결을 확정한다.
    ///
    /// 토큰 미보유 시 브라우저 창이 열린다.
    /// listTools 한 번 호출로 연결이 실제로 동작하는지 검증 후 disconnect한다.
    /// 실패 시 throw — 호출 측(UI)이 에러를 표시한다.
    public func connect() async throws {
        let client = try await makeConnectedClient(interactive: true)
        defer { Task { await client.disconnect() } }
        // 연결 검증 + notion-search 도구가 실제로 노출되는지 확인(권한 축소·스펙 변경 조기 감지).
        let toolList = try await client.listTools()
        guard toolList.tools.contains(where: { $0.name == Self.searchToolName }) else {
            throw NotionMCPError.searchToolUnavailable
        }
        isConnected = tokenStorage.load() != nil
    }

    /// Keychain 토큰을 삭제하고 연결 상태를 해제한다.
    public func disconnect() {
        tokenStorage.clear()
        isConnected = false
    }

    /// 전사 키워드로 Notion 페이지를 검색한다.
    ///
    /// isConnected가 false거나 오류 발생 시 빈 배열로 fail-soft.
    /// 쿼리·토큰은 절대 로그에 남기지 않는다.
    public func search(_ query: String, limit: Int = 5) async -> [RelatedDoc] {
        guard isConnected else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            // 검색은 비대화형: 토큰 만료·갱신 실패 시 브라우저를 띄우지 않고 조용히 실패.
            let client = try await makeConnectedClient(interactive: false)
            defer { Task { await client.disconnect() } }

            let result = try await client.callTool(
                name: Self.searchToolName,
                arguments: ["query": .string(trimmed)]
            )

            // content 배열에서 .text 케이스를 모아 텍스트를 조합한다.
            let combinedText = result.content.compactMap { item -> String? in
                if case let .text(text, _, _) = item { return text }
                return nil
            }.joined(separator: "\n")

            return Self.parseSearchResults(combinedText, limit: limit)
        } catch {
            // 쿼리·토큰 유출 방지: 타입 이름만 기록
            let typeName = String(describing: type(of: error))
            FileHandle.standardError.write(Data("[NotionMCP] 검색 오류(type=\(typeName))\n".utf8))
            return []
        }
    }

    // MARK: - 파싱 (테스트 대상)

    /// notion-search 응답 텍스트를 RelatedDoc 배열로 변환한다.
    ///
    /// 서버 응답 포맷이 라이브로 검증되지 않았으므로 두 단계 방어적 파싱을 적용한다:
    ///   1순위) JSON 파싱: results 배열에서 title/url 추출 (포맷 A: {results:[{title,url}]})
    ///   2순위) URL 정규식 폴백: notion.so/... URL을 추출하고 주변 텍스트를 title로 사용
    ///   둘 다 실패해도 throw 없이 빈 배열 반환.
    nonisolated public static func parseSearchResults(_ text: String, limit: Int) -> [RelatedDoc] {
        // 1. JSON 파싱 시도
        if let data = text.data(using: .utf8),
           let docs = parseJSON(data, limit: limit), !docs.isEmpty
        {
            return docs
        }

        // 2. URL 정규식 폴백
        return parseWithRegex(text, limit: limit)
    }

    /// JSON 응답에서 title·url을 추출한다.
    /// results 배열 구조: [{title, url}] 또는 [{title, url, ...}]
    nonisolated private static func parseJSON(_ data: Data, limit: Int) -> [RelatedDoc]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], !results.isEmpty
        else { return nil }

        let docs = results.prefix(limit).compactMap { item -> RelatedDoc? in
            guard let url = item["url"] as? String, !url.isEmpty else { return nil }
            let title = item["title"] as? String
                ?? item["name"] as? String
                ?? "(제목 없음)"
            return RelatedDoc(source: .notion, title: title, url: url)
        }
        return docs.isEmpty ? nil : docs
    }

    /// notion.so URL을 정규식으로 추출하고, 주변 텍스트를 title로 활용한다.
    nonisolated private static func parseWithRegex(_ text: String, limit: Int) -> [RelatedDoc] {
        // notion.so/로 시작하는 URL 패턴 (http(s)://www.notion.so/... 또는 notion.so/...)
        let pattern = #"https?://(?:www\.)?notion\.so/[^\s\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var docs: [RelatedDoc] = []
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:\"'!?)]>")
        for match in matches.prefix(limit) {
            // 문장 끝·마크다운·JSON에서 URL 뒤에 붙는 구두점을 제거(오버매칭 방지).
            let urlString = nsText.substring(with: match.range)
                .trimmingCharacters(in: trailingPunctuation)
            // URL 앞 텍스트 한 줄을 title로 시도
            let matchStart = match.range.location
            let precedingRange = NSRange(location: max(0, matchStart - 120), length: min(120, matchStart))
            let preceding = nsText.substring(with: precedingRange)
            let candidateTitle = preceding
                .components(separatedBy: .newlines)
                .last?
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*#>|"))
                .trimmingCharacters(in: .whitespaces)
            let title = (candidateTitle?.isEmpty == false) ? candidateTitle! : "(제목 없음)"
            docs.append(RelatedDoc(source: .notion, title: title, url: urlString))
        }
        return docs
    }
}

// MARK: - 에러 타입

enum NotionMCPError: Error, LocalizedError {
    case searchToolUnavailable

    var errorDescription: String? {
        switch self {
        case .searchToolUnavailable:
            return "이 Notion 연결에서 검색 도구를 사용할 수 없습니다."
        }
    }
}
