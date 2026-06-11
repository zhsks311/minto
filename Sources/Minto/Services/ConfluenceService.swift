import Foundation

protocol ConfluenceHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

final class URLSessionConfluenceHTTPClient: ConfluenceHTTPClient, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

protocol ConfluenceTokenStorageBackend: Sendable {
    func exists(account: String) -> Bool
    func load(account: String) -> Data?
    func save(account: String, data: Data)
    func delete(account: String)
}

struct SecretStoreConfluenceTokenStorageBackend: ConfluenceTokenStorageBackend {
    private let secretStore: any SecretStore

    init(secretStore: any SecretStore = SecretStoreFactory.make()) {
        self.secretStore = secretStore
    }

    func exists(account: String) -> Bool {
        secretStore.exists(account: account, service: KeychainService.oauthService)
    }

    func load(account: String) -> Data? {
        secretStore.load(account: account, service: KeychainService.oauthService)
    }

    func save(account: String, data: Data) {
        _ = secretStore.save(account: account, data: data, service: KeychainService.oauthService)
    }

    func delete(account: String) {
        _ = secretStore.delete(account: account, service: KeychainService.oauthService)
    }
}

/// Confluence Cloud REST API(CQL 검색)로 페이지를 조회한다.
///
/// 인증(OAuth 3LO 대신 Basic): 사용자가
/// https://id.atlassian.com/manage-profile/security/api-tokens 에서 API token을 발급받아
/// 설정에 site URL(`https://your.atlassian.net`)·email과 함께 입력한다.
/// API token만 비밀이라 Keychain, site URL·email은 UserDefaults에 둔다.
@MainActor
public final class ConfluenceService: ObservableObject {
    public static let shared = ConfluenceService()

    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connected
        case needsReconnect
    }

    public struct ContextDocument: Identifiable, Sendable, Hashable {
        public var id: String { url }
        public let title: String
        public let text: String
        public let url: String

        public init(title: String, text: String, url: String) {
            self.title = title
            self.text = text
            self.url = url
        }
    }

    public struct ContextSearchResult: Sendable, Equatable {
        public let documents: [ContextDocument]
        public let failure: SearchFailure?

        public init(documents: [ContextDocument], failure: SearchFailure?) {
            self.documents = documents
            self.failure = failure
        }
    }

    public enum SearchFailure: Equatable, Sendable {
        case unauthorized
        case forbidden
        case network
    }

    public enum CredentialValidationOutcome: Equatable, Sendable {
        case success
        case unauthorized
        case forbidden
        case invalidURL
        case network

        public var message: String {
            switch self {
            case .success:
                return "Confluence 연결을 확인했어요."
            case .unauthorized:
                return "이메일이나 API token이 올바르지 않아요."
            case .forbidden:
                return "계정 권한이나 조직 정책으로 거부됐어요."
            case .invalidURL:
                return "Confluence Cloud 사이트 URL을 확인하세요."
            case .network:
                return "Confluence에 연결하지 못했어요. 네트워크를 확인해 주세요."
            }
        }
    }

    public struct PublishedPage: Sendable, Equatable {
        public let id: String
        public let title: String
        public let url: String
    }

    public enum ExportError: Error, LocalizedError, Sendable, Equatable {
        case notConfigured
        case invalidDestination
        case spaceNotFound(String)
        case badResponse
        case httpStatus(Int)
        case unauthorized
        case forbidden
        case contentTooLarge
        case rateLimited
        case network

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Confluence 연결 정보가 필요해요."
            case .invalidDestination:
                return "내보낼 공간 키를 확인하세요."
            case .spaceNotFound(let spaceKey):
                return "Confluence 공간을 찾지 못했어요: \(spaceKey)"
            case .badResponse:
                return "Confluence 응답을 이해하지 못했어요."
            case .httpStatus(let status):
                return "Confluence 내보내기가 실패했어요. HTTP \(status)"
            case .unauthorized:
                return "Confluence 토큰이나 이메일을 다시 확인하세요."
            case .forbidden:
                return "이 공간에 페이지를 만들 권한이 없어요."
            case .contentTooLarge:
                return "회의록이 너무 커서 Confluence에 보낼 수 없어요."
            case .rateLimited:
                return "Confluence 요청이 잠시 제한됐어요. 잠시 후 다시 시도하세요."
            case .network:
                return "Confluence에 연결하지 못했어요."
            }
        }
    }

    static let baseURLKey = "confluenceBaseURL"
    static let emailKey = "confluenceEmail"
    private let keychainKey = "confluence"
    private let httpClient: any ConfluenceHTTPClient
    private let defaults: UserDefaults
    private let tokenStorage: any ConfluenceTokenStorageBackend

    /// 토큰 존재 여부 캐시 — isConfigured가 매 렌더마다 Keychain을 읽지 않도록 init에서 1회 로드.
    @Published private var hasToken: Bool = false
    @Published private var needsReconnect: Bool = false
    private var cachedAPIToken: String?

    public convenience init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.init(
            httpClient: URLSessionConfluenceHTTPClient(session: session),
            defaults: defaults,
            tokenStorage: SecretStoreConfluenceTokenStorageBackend()
        )
    }

    init(
        httpClient: any ConfluenceHTTPClient,
        defaults: UserDefaults = .standard,
        tokenStorage: any ConfluenceTokenStorageBackend
    ) {
        self.httpClient = httpClient
        self.defaults = defaults
        self.tokenStorage = tokenStorage
        self.cachedAPIToken = nil
        self.hasToken = tokenStorage.exists(account: keychainKey)
    }

    // MARK: - 자격 관리

    /// 토큰 원문은 외부로 노출하지 않는다(로그·UI 유출 방지). search() 내부에서만 사용.
    private var apiToken: String? {
        guard !needsReconnect else { return nil }
        if let cachedAPIToken { return cachedAPIToken }
        let hadToken = hasToken
        let token = Self.loadAPIToken(keychainKey: keychainKey, tokenStorage: tokenStorage)
        if token == nil, hadToken {
            markNeedsReconnect()
            return nil
        }
        cachedAPIToken = token
        hasToken = (token != nil)
        return token
    }

    private static func loadAPIToken(
        keychainKey: String,
        tokenStorage: any ConfluenceTokenStorageBackend
    ) -> String? {
        guard let data = tokenStorage.load(account: keychainKey) else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    public var email: String? {
        let value = defaults.string(forKey: Self.emailKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// 입력 URL을 `https://site.atlassian.net` 형태로 정규화(`/wiki` 이하 경로·끝의 `/` 제거).
    public var baseURL: String? {
        guard let value = defaults.string(forKey: Self.baseURLKey) else { return nil }
        return Self.normalizedBaseURL(from: value)
    }

    /// hasToken은 캐시(Keychain 비접근), email·baseURL은 UserDefaults(인메모리)라 렌더 경로에서 가볍다.
    public var isConfigured: Bool {
        connectionState == .connected
    }

    public var connectionState: ConnectionState {
        if needsReconnect { return .needsReconnect }
        return hasToken && email != nil && baseURL != nil ? .connected : .disconnected
    }

    public var canDisconnect: Bool {
        hasToken || needsReconnect
    }

    public var hasStoredAPIToken: Bool {
        hasToken
    }

    public func setAPIToken(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tokenStorage.delete(account: keychainKey)
        } else {
            tokenStorage.save(account: keychainKey, data: Data(trimmed.utf8))
        }
        cachedAPIToken = trimmed.isEmpty ? nil : trimmed
        hasToken = !trimmed.isEmpty  // @Published라 objectWillChange 자동 발행
        needsReconnect = false
    }

    public func disconnect() {
        tokenStorage.delete(account: keychainKey)
        defaults.removeObject(forKey: Self.baseURLKey)
        defaults.removeObject(forKey: Self.emailKey)
        cachedAPIToken = nil
        needsReconnect = false
        hasToken = false
    }

    public func setEmail(_ raw: String) {
        defaults.set(raw.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.emailKey)
        needsReconnect = false
        objectWillChange.send()
    }

    public func setBaseURL(_ raw: String) {
        defaults.set(raw.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.baseURLKey)
        needsReconnect = false
        objectWillChange.send()
    }

    private func markNeedsReconnect() {
        cachedAPIToken = nil
        needsReconnect = true
    }

    public func validateCredentials(
        baseURL rawBaseURL: String,
        email rawEmail: String,
        token rawToken: String
    ) async -> CredentialValidationOutcome {
        guard let baseURL = Self.normalizedBaseURL(from: rawBaseURL),
              Self.isAllowedCloudBaseURL(baseURL),
              let url = URL(string: "\(baseURL)/wiki/rest/api/user/current") else {
            return .invalidURL
        }

        let trimmedEmail = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentialToken: String
        if inputToken.isEmpty {
            guard let storedToken = Self.loadAPIToken(keychainKey: keychainKey, tokenStorage: tokenStorage) else {
                return .unauthorized
            }
            credentialToken = storedToken
        } else {
            credentialToken = inputToken
        }
        guard !trimmedEmail.isEmpty, !credentialToken.isEmpty else { return .unauthorized }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credential = Data("\(trimmedEmail):\(credentialToken)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await httpClient.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .network }
            switch http.statusCode {
            case 200...299:
                return .success
            case 401:
                return .unauthorized
            case 403:
                return .forbidden
            default:
                return .network
            }
        } catch {
            return .network
        }
    }

    // MARK: - 검색

    /// 전사 키워드로 Confluence 페이지를 CQL 검색한다.
    /// 자격 미설정·빈 쿼리·오류는 모두 빈 배열로 fail-soft.
    public func search(_ query: String, limit: Int = 5) async -> [RelatedDoc] {
        await searchHitResult(query, limit: limit).hits.map(\.relatedDoc)
    }

    /// 회의 시작 전 참고 문맥으로 쓸 Confluence 문서 본문을 조회한다.
    /// 본문 조회가 실패하면 검색 excerpt라도 참고자료로 사용한다.
    public func searchContext(_ query: String, limit: Int = 3) async -> ContextSearchResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = apiToken, let email, let baseURL, !trimmedQuery.isEmpty,
              Self.isAllowedCloudBaseURL(baseURL) else {
            return ContextSearchResult(documents: [], failure: nil)
        }
        let result = await searchHitResult(trimmedQuery, limit: limit, token: token, email: email, baseURL: baseURL)
        guard result.failure == nil else {
            return ContextSearchResult(documents: [], failure: result.failure)
        }

        var documents: [ContextDocument] = []
        for hit in result.hits {
            let body: String?
            if let contentID = hit.contentID {
                body = await fetchPageBody(contentID: contentID, token: token, email: email, baseURL: baseURL)
            } else {
                body = nil
            }
            let text = Self.contextText(body: body, snippet: hit.snippet)
            guard !text.isEmpty else { continue }
            documents.append(ContextDocument(title: hit.title, text: text, url: hit.url))
        }
        return ContextSearchResult(documents: documents, failure: nil)
    }

    public func publishPage(
        title: String,
        markdown: String,
        spaceKey: String,
        parentID: String? = nil
    ) async throws -> PublishedPage {
        guard let token = apiToken, let email, let baseURL else {
            throw ExportError.notConfigured
        }
        let cleanedSpaceKey = spaceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSpaceKey.isEmpty, !cleanedTitle.isEmpty, Self.isAllowedCloudBaseURL(baseURL) else {
            throw ExportError.invalidDestination
        }

        let spaceID = try await resolveSpaceID(spaceKey: cleanedSpaceKey, token: token, email: email, baseURL: baseURL)

        guard let url = URL(string: "\(baseURL)/wiki/api/v2/pages") else {
            throw ExportError.invalidDestination
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-check", forHTTPHeaderField: "X-Atlassian-Token")
        let credential = Data("\(email):\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Self.createPagePayload(
            title: cleanedTitle,
            markdown: markdown,
            spaceID: spaceID,
            parentID: parentID
        )

        do {
            let (data, response) = try await httpClient.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ExportError.badResponse }
            guard (200...299).contains(http.statusCode) else {
                FileHandle.standardError.write(Data("[Confluence] 내보내기 HTTP \(http.statusCode)\n".utf8))
                if http.statusCode == 401 {
                    markNeedsReconnect()
                }
                throw Self.exportError(forHTTPStatus: http.statusCode)
            }
            guard let page = Self.parsePublishedPage(data, fallbackBase: "\(baseURL)/wiki") else {
                throw ExportError.badResponse
            }
            return page
        } catch let error as ExportError {
            throw error
        } catch {
            let code = (error as? URLError)?.code.rawValue ?? -1
            FileHandle.standardError.write(Data("[Confluence] 내보내기 네트워크 오류(code=\(code))\n".utf8))
            throw ExportError.network
        }
    }

    private func resolveSpaceID(
        spaceKey: String,
        token: String,
        email: String,
        baseURL: String
    ) async throws -> String {
        var components = URLComponents(string: "\(baseURL)/wiki/api/v2/spaces")
        components?.queryItems = [
            URLQueryItem(name: "keys", value: spaceKey),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else {
            throw ExportError.invalidDestination
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credential = Data("\(email):\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await httpClient.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ExportError.badResponse }
            guard (200...299).contains(http.statusCode) else {
                FileHandle.standardError.write(Data("[Confluence] 공간 조회 HTTP \(http.statusCode)\n".utf8))
                if http.statusCode == 401 {
                    markNeedsReconnect()
                }
                throw Self.exportError(forHTTPStatus: http.statusCode)
            }
            guard let spaceID = Self.parseSpaceID(data, matchingKey: spaceKey) else {
                throw ExportError.spaceNotFound(spaceKey)
            }
            return spaceID
        } catch let error as ExportError {
            throw error
        } catch {
            let code = (error as? URLError)?.code.rawValue ?? -1
            FileHandle.standardError.write(Data("[Confluence] 공간 조회 네트워크 오류(code=\(code))\n".utf8))
            throw ExportError.network
        }
    }

    private func searchHitResult(_ query: String, limit: Int) async -> ConfluenceSearchHitResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = apiToken, let email, let baseURL, !trimmedQuery.isEmpty,
              Self.isAllowedCloudBaseURL(baseURL) else {
            return ConfluenceSearchHitResult(hits: [], failure: nil)
        }
        return await searchHitResult(trimmedQuery, limit: limit, token: token, email: email, baseURL: baseURL)
    }

    private func searchHitResult(
        _ trimmedQuery: String,
        limit: Int,
        token: String,
        email: String,
        baseURL: String
    ) async -> ConfluenceSearchHitResult {
        let cql = Self.cqlQuery(for: trimmedQuery)

        var components = URLComponents(string: "\(baseURL)/wiki/rest/api/search")
        components?.queryItems = [
            URLQueryItem(name: "cql", value: cql),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else {
            return ConfluenceSearchHitResult(hits: [], failure: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credential = Data("\(email):\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await httpClient.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ConfluenceSearchHitResult(hits: [], failure: .network)
            }
            guard http.statusCode == 200 else {
                FileHandle.standardError.write(Data("[Confluence] 검색 HTTP \(http.statusCode)\n".utf8))
                if http.statusCode == 401 || http.statusCode == 403 {
                    markNeedsReconnect()
                }
                switch http.statusCode {
                case 401:
                    return ConfluenceSearchHitResult(hits: [], failure: .unauthorized)
                case 403:
                    return ConfluenceSearchHitResult(hits: [], failure: .forbidden)
                default:
                    return ConfluenceSearchHitResult(hits: [], failure: .network)
                }
            }
            return ConfluenceSearchHitResult(
                hits: Self.parseSearchHits(data, fallbackBase: "\(baseURL)/wiki", limit: limit),
                failure: nil
            )
        } catch {
            // URL 쿼리스트링에 CQL(전사 내용)이 실리므로 localizedDescription 대신 코드만 기록.
            let code = (error as? URLError)?.code.rawValue ?? -1
            FileHandle.standardError.write(Data("[Confluence] 검색 네트워크 오류(code=\(code))\n".utf8))
            return ConfluenceSearchHitResult(hits: [], failure: .network)
        }
    }

    private func fetchPageBody(contentID: String, token: String, email: String, baseURL: String) async -> String? {
        guard let escapedID = contentID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        var components = URLComponents(string: "\(baseURL)/wiki/rest/api/content/\(escapedID)")
        components?.queryItems = [
            URLQueryItem(name: "expand", value: "body.storage")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credential = Data("\(email):\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await httpClient.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard http.statusCode == 200 else {
                FileHandle.standardError.write(Data("[Confluence] 본문 HTTP \(http.statusCode)\n".utf8))
                if http.statusCode == 401 {
                    markNeedsReconnect()
                }
                return nil
            }
            return Self.parseContentBodyText(data)
        } catch {
            let code = (error as? URLError)?.code.rawValue ?? -1
            FileHandle.standardError.write(Data("[Confluence] 본문 네트워크 오류(code=\(code))\n".utf8))
            return nil
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

    nonisolated static func isAllowedCloudBaseURL(_ baseURL: String) -> Bool {
        guard let components = URLComponents(string: baseURL),
              components.scheme == "https",
              components.path.isEmpty || components.path == "/",
              let host = components.host?.lowercased(),
              host.hasSuffix(".atlassian.net") else {
            return false
        }
        return host.split(separator: ".").count >= 3
    }

    nonisolated static func normalizedBaseURL(from raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        // `/wiki`, `/wiki/`, `/wiki/spaces/...` 등 컨텍스트 경로를 모두 잘라낸다.
        if let range = value.range(of: "/wiki") {
            value = String(value[..<range.lowerBound])
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? nil : value
    }

    nonisolated static func createPagePayload(
        title: String,
        markdown: String,
        spaceID: String,
        parentID: String?
    ) throws -> Data {
        var payload: [String: Any] = [
            "status": "current",
            "title": title,
            "spaceId": spaceID,
            "body": [
                "representation": "storage",
                "value": storageHTML(fromMarkdown: markdown)
            ]
        ]
        let cleanedParentID = parentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanedParentID.isEmpty {
            payload["parentId"] = cleanedParentID
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    nonisolated static func storageHTML(fromMarkdown markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var html: [String] = []
        var listOpen = false

        func closeListIfNeeded() {
            if listOpen {
                html.append("</ul>")
                listOpen = false
            }
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                closeListIfNeeded()
                continue
            }
            if line.hasPrefix("### ") {
                closeListIfNeeded()
                html.append("<h3>\(inlineHTML(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("## ") {
                closeListIfNeeded()
                html.append("<h2>\(inlineHTML(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("# ") {
                closeListIfNeeded()
                html.append("<h1>\(inlineHTML(String(line.dropFirst(2))))</h1>")
            } else if line.hasPrefix("- [ ] ") {
                if !listOpen {
                    html.append("<ul>")
                    listOpen = true
                }
                html.append("<li>[ ] \(inlineHTML(String(line.dropFirst(6))))</li>")
            } else if line.hasPrefix("- ") {
                if !listOpen {
                    html.append("<ul>")
                    listOpen = true
                }
                html.append("<li>\(inlineHTML(String(line.dropFirst(2))))</li>")
            } else {
                closeListIfNeeded()
                html.append("<p>\(inlineHTML(line))</p>")
            }
        }
        closeListIfNeeded()
        return html.joined(separator: "\n")
    }

    // MARK: - 파싱(테스트 대상)

    /// Confluence `/wiki/rest/api/search` 응답을 RelatedDoc 배열로 변환한다.
    /// 절대 URL은 응답의 `_links.base`(없으면 fallbackBase) + 결과별 상대 `url`로 조립한다.
    nonisolated static func parse(_ data: Data, fallbackBase: String, limit: Int) -> [RelatedDoc] {
        parseSearchHits(data, fallbackBase: fallbackBase, limit: limit).map(\.relatedDoc)
    }

    nonisolated static func parseContentBodyText(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["body"] as? [String: Any] else {
            return nil
        }
        let storage = body["storage"] as? [String: Any]
        let view = body["view"] as? [String: Any]
        let html = (storage?["value"] as? String) ?? (view?["value"] as? String)
        guard let html else { return nil }
        let text = htmlToPlainText(html)
        return text.isEmpty ? nil : text
    }

    nonisolated static func parseSpaceID(_ data: Data, matchingKey requestedKey: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return nil
        }
        let requested = requestedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = results.first { item in
            guard let key = item["key"] as? String else { return false }
            return key.compare(requested, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return match?["id"] as? String
    }

    nonisolated static func parsePublishedPage(_ data: Data, fallbackBase: String) -> PublishedPage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            return nil
        }
        let title = (json["title"] as? String) ?? "(제목 없음)"
        let links = json["_links"] as? [String: Any]
        let base = (links?["base"] as? String) ?? fallbackBase
        let webui = (links?["webui"] as? String) ?? "/pages/viewpage.action?pageId=\(id)"
        let url = webui.hasPrefix("http") ? webui : base + (webui.hasPrefix("/") ? webui : "/" + webui)
        return PublishedPage(id: id, title: title, url: url)
    }

    nonisolated public static func contextBlock(from documents: [ContextDocument], maxCharacters: Int = 3500) -> String {
        let blocks = documents.map { doc in
            """
            - \(doc.title)
              URL: \(doc.url)
              내용: \(doc.text)
            """
        }
        let joined = blocks.joined(separator: "\n")
        guard !joined.isEmpty else { return "" }
        let capped = String(joined.prefix(maxCharacters))
        return "[Confluence 참고 문서]\n\(capped)"
    }

    nonisolated private static func parseSearchHits(_ data: Data, fallbackBase: String, limit: Int) -> [ConfluenceSearchHit] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        let links = json["_links"] as? [String: Any]
        let base = (links?["base"] as? String) ?? fallbackBase

        return results.prefix(limit).compactMap { result -> ConfluenceSearchHit? in
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
            let contentID = (content?["id"] as? String)
                ?? (result["contentId"] as? String)
                ?? (result["id"] as? String)
            return ConfluenceSearchHit(
                contentID: contentID,
                title: title,
                snippet: snippet,
                url: fullURL
            )
        }
    }

    nonisolated private static func contextText(body: String?, snippet: String) -> String {
        let raw = body?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        if raw.count <= 1200 { return raw }
        return "\(raw.prefix(1200))..."
    }

    /// excerpt는 매치 하이라이트용 `@@@hl@@@` 마커가 섞여 오므로 제거한다.
    nonisolated private static func plainExcerpt(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw
            .replacingOccurrences(of: "@@@hl@@@", with: "")
            .replacingOccurrences(of: "@@@endhl@@@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func htmlToPlainText(_ html: String) -> String {
        var text = html
        text = regexReplace(text, pattern: "(?i)<\\s*(br|/p|/div|/li|/h[1-6]|/tr)\\s*/?>", with: "\n")
        text = regexReplace(text, pattern: "(?i)<\\s*li[^>]*>", with: "\n- ")
        text = regexReplace(text, pattern: "<[^>]+>", with: " ")
        text = decodeHTMLEntities(text)
        let lines = text
            .components(separatedBy: .newlines)
            .map { line in
                let normalized = line
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return collapseKoreanParticleSpacing(normalized)
            }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    nonisolated private static func collapseKoreanParticleSpacing(_ text: String) -> String {
        regexReplace(text, pattern: #"([가-힣A-Za-z0-9])\s+([은는이가을를])(?=\s|$)"#, with: "$1$2")
    }

    nonisolated private static func regexReplace(_ text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    nonisolated private static func decodeHTMLEntities(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        let numericPattern = #"&#(\d+);"#
        guard let regex = try? NSRegularExpression(pattern: numericPattern) else { return decoded }
        let matches = regex.matches(in: decoded, range: NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)).reversed()
        for match in matches {
            guard match.numberOfRanges == 2,
                  let valueRange = Range(match.range(at: 1), in: decoded),
                  let fullRange = Range(match.range(at: 0), in: decoded),
                  let scalarValue = UInt32(decoded[valueRange]),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            decoded.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return decoded
    }

    nonisolated private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    nonisolated private static func exportError(forHTTPStatus status: Int) -> ExportError {
        switch status {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 413:
            return .contentTooLarge
        case 429:
            return .rateLimited
        default:
            return .httpStatus(status)
        }
    }

    nonisolated private static func inlineHTML(_ markdown: String) -> String {
        var text = escapeHTML(markdown)
        text = replaceDelimited(text, delimiter: "**", openTag: "<strong>", closeTag: "</strong>")
        text = replaceDelimited(text, delimiter: "`", openTag: "<code>", closeTag: "</code>")
        return text
    }

    nonisolated private static func replaceDelimited(
        _ text: String,
        delimiter: String,
        openTag: String,
        closeTag: String
    ) -> String {
        var remaining = text[...]
        var output = ""

        while let start = remaining.range(of: delimiter) {
            output += String(remaining[..<start.lowerBound])
            let afterStart = remaining[start.upperBound...]
            guard let end = afterStart.range(of: delimiter) else {
                output += String(remaining[start.lowerBound...])
                return output
            }
            output += openTag + String(afterStart[..<end.lowerBound]) + closeTag
            remaining = afterStart[end.upperBound...]
        }
        output += String(remaining)
        return output
    }
}

private struct ConfluenceSearchHit: Sendable, Hashable {
    let contentID: String?
    let title: String
    let snippet: String
    let url: String

    var relatedDoc: RelatedDoc {
        RelatedDoc(source: .confluence, title: title, snippet: snippet, url: url)
    }
}

private struct ConfluenceSearchHitResult: Sendable {
    let hits: [ConfluenceSearchHit]
    let failure: ConfluenceService.SearchFailure?
}
