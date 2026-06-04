import Foundation

/// Confluence Cloud REST API(CQL 검색)로 페이지를 조회한다.
///
/// 인증(OAuth 3LO 대신 Basic): 사용자가
/// https://id.atlassian.com/manage-profile/security/api-tokens 에서 API token을 발급받아
/// 설정에 site URL(`https://your.atlassian.net`)·email과 함께 입력한다.
/// API token만 비밀이라 Keychain, site URL·email은 UserDefaults에 둔다.
@MainActor
public final class ConfluenceService: ObservableObject {
    public static let shared = ConfluenceService()

    static let baseURLKey = "confluenceBaseURL"
    static let emailKey = "confluenceEmail"
    private let keychainKey = "confluence"
    private let session: URLSession
    private let defaults: UserDefaults

    /// 토큰 존재 여부 캐시 — isConfigured가 매 렌더마다 Keychain을 읽지 않도록 init에서 1회 로드.
    @Published private var hasToken: Bool = false

    public init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        self.hasToken = (apiToken != nil)
    }

    // MARK: - 자격 관리

    /// 토큰 원문은 외부로 노출하지 않는다(로그·UI 유출 방지). search() 내부에서만 사용.
    private var apiToken: String? {
        guard let data = KeychainService.load(provider: keychainKey) else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    public var email: String? {
        let value = defaults.string(forKey: Self.emailKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// 입력 URL을 `https://site.atlassian.net` 형태로 정규화(`/wiki` 이하 경로·끝의 `/` 제거).
    public var baseURL: String? {
        guard var value = defaults.string(forKey: Self.baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        // `/wiki`, `/wiki/`, `/wiki/spaces/...` 등 컨텍스트 경로를 모두 잘라낸다.
        if let range = value.range(of: "/wiki") {
            value = String(value[..<range.lowerBound])
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? nil : value
    }

    /// hasToken은 캐시(Keychain 비접근), email·baseURL은 UserDefaults(인메모리)라 렌더 경로에서 가볍다.
    public var isConfigured: Bool {
        hasToken && email != nil && baseURL != nil
    }

    public func setAPIToken(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainService.delete(provider: keychainKey)
        } else {
            KeychainService.save(provider: keychainKey, data: Data(trimmed.utf8))
        }
        hasToken = !trimmed.isEmpty  // @Published라 objectWillChange 자동 발행
    }

    public func setEmail(_ raw: String) {
        defaults.set(raw.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.emailKey)
        objectWillChange.send()
    }

    public func setBaseURL(_ raw: String) {
        defaults.set(raw.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.baseURLKey)
        objectWillChange.send()
    }

    // MARK: - 검색

    /// 전사 키워드로 Confluence 페이지를 CQL 검색한다.
    /// 자격 미설정·빈 쿼리·오류는 모두 빈 배열로 fail-soft.
    public func search(_ query: String, limit: Int = 5) async -> [RelatedDoc] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = apiToken, let email, let baseURL, !trimmedQuery.isEmpty else { return [] }

        let cql = Self.cqlQuery(for: trimmedQuery)

        var components = URLComponents(string: "\(baseURL)/wiki/rest/api/search")
        components?.queryItems = [
            URLQueryItem(name: "cql", value: cql),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credential = Data("\(email):\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return [] }
            guard http.statusCode == 200 else {
                FileHandle.standardError.write(Data("[Confluence] 검색 HTTP \(http.statusCode)\n".utf8))
                return []
            }
            return Self.parse(data, fallbackBase: "\(baseURL)/wiki", limit: limit)
        } catch {
            // URL 쿼리스트링에 CQL(전사 내용)이 실리므로 localizedDescription 대신 코드만 기록.
            let code = (error as? URLError)?.code.rawValue ?? -1
            FileHandle.standardError.write(Data("[Confluence] 검색 네트워크 오류(code=\(code))\n".utf8))
            return []
        }
    }

    /// 검색어를 CQL `text ~ "..."` 문자열로 만든다.
    /// 큰따옴표 리터럴 안에서 안전하도록 `\` 와 `"` 를 이스케이프(순서 중요: `\` 먼저).
    /// 따옴표를 단순 제거하면 입력 끝의 `\` 가 닫는 따옴표를 이스케이프해 구문이 깨지고,
    /// 이스케이프하면 `AND`·`type=page` 같은 예약어도 리터럴로만 취급돼 인젝션이 차단된다.
    nonisolated static func cqlQuery(for query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "text ~ \"\(escaped)\""
    }

    // MARK: - 파싱(테스트 대상)

    /// Confluence `/wiki/rest/api/search` 응답을 RelatedDoc 배열로 변환한다.
    /// 절대 URL은 응답의 `_links.base`(없으면 fallbackBase) + 결과별 상대 `url`로 조립한다.
    nonisolated static func parse(_ data: Data, fallbackBase: String, limit: Int) -> [RelatedDoc] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        let links = json["_links"] as? [String: Any]
        let base = (links?["base"] as? String) ?? fallbackBase

        return results.prefix(limit).compactMap { result -> RelatedDoc? in
            let content = result["content"] as? [String: Any]
            let title = (content?["title"] as? String)
                ?? (result["title"] as? String)
                ?? "(제목 없음)"
            guard let relativePath = result["url"] as? String, !relativePath.isEmpty else { return nil }
            let fullURL: String
            if relativePath.hasPrefix("http") {
                fullURL = relativePath
            } else {
                // 상대 경로가 `/`로 시작하지 않아도 base와 안전하게 결합.
                fullURL = base + (relativePath.hasPrefix("/") ? relativePath : "/" + relativePath)
            }
            let snippet = Self.plainExcerpt(result["excerpt"] as? String)
            return RelatedDoc(source: .confluence, title: title, snippet: snippet, url: fullURL)
        }
    }

    /// excerpt는 매치 하이라이트용 `@@@hl@@@` 마커가 섞여 오므로 제거한다.
    nonisolated private static func plainExcerpt(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw
            .replacingOccurrences(of: "@@@hl@@@", with: "")
            .replacingOccurrences(of: "@@@endhl@@@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
