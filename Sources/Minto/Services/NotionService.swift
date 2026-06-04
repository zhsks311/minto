import Foundation

/// Notion integration token으로 페이지를 검색한다.
///
/// 인증: 사용자가 https://www.notion.so/my-integrations 에서 internal integration을
/// 만들고 발급받은 토큰(`ntn_...`/`secret_...`)을 설정에 입력 → Keychain에 저장.
/// 해당 integration이 공유받은 페이지만 검색된다(Notion 권한 모델).
@MainActor
public final class NotionService: ObservableObject {
    public static let shared = NotionService()

    private let keychainKey = "notion"
    private let session: URLSession

    /// 토큰 존재 여부 캐시 — 매 렌더마다 Keychain을 읽지 않도록 init에서 1회만 로드(기존 OAuth 서비스 패턴).
    @Published public private(set) var isConfigured: Bool = false

    /// 테스트에서 토큰 입력을 우회하기 위한 주입 지점(기본은 Keychain 사용).
    public init(session: URLSession = .shared) {
        self.session = session
        self.isConfigured = (token != nil)
    }

    // MARK: - 토큰 관리

    /// 토큰 원문은 외부로 노출하지 않는다(로그·UI 유출 방지). search() 내부에서만 사용.
    private var token: String? {
        guard let data = KeychainService.load(provider: keychainKey) else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    public func setToken(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainService.delete(provider: keychainKey)
        } else {
            KeychainService.save(provider: keychainKey, data: Data(trimmed.utf8))
        }
        isConfigured = !trimmed.isEmpty  // @Published라 objectWillChange 자동 발행
    }

    // MARK: - 검색

    /// 전사 키워드로 Notion 페이지를 검색해 관련 문서를 반환한다.
    /// 토큰 미설정·빈 쿼리·오류는 모두 빈 배열로 fail-soft(회의 흐름을 막지 않는다).
    public func search(_ query: String, limit: Int = 5) async -> [RelatedDoc] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !trimmedQuery.isEmpty else { return [] }

        guard let url = URL(string: "https://api.notion.com/v1/search") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "query": trimmedQuery,
            "page_size": limit,
            "filter": ["property": "object", "value": "page"]
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return [] }
        request.httpBody = httpBody

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return [] }
            guard http.statusCode == 200 else {
                FileHandle.standardError.write(Data("[Notion] 검색 HTTP \(http.statusCode)\n".utf8))
                return []
            }
            return Self.parse(data, limit: limit)
        } catch {
            // 쿼리(회의 전사) 내용이 섞일 수 있는 localizedDescription 대신 코드만 기록.
            let code = (error as? URLError)?.code.rawValue ?? -1
            FileHandle.standardError.write(Data("[Notion] 검색 네트워크 오류(code=\(code))\n".utf8))
            return []
        }
    }

    // MARK: - 파싱(테스트 대상)

    /// Notion `/v1/search` 응답 JSON을 RelatedDoc 배열로 변환한다.
    nonisolated static func parse(_ data: Data, limit: Int) -> [RelatedDoc] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        return results.prefix(limit).compactMap { page -> RelatedDoc? in
            let urlString = page["url"] as? String ?? ""
            guard !urlString.isEmpty else { return nil }
            return RelatedDoc(source: .notion, title: title(from: page), url: urlString)
        }
    }

    /// 페이지의 properties에서 type == "title" 인 속성의 plain_text를 이어 붙인다.
    nonisolated private static func title(from page: [String: Any]) -> String {
        guard let properties = page["properties"] as? [String: Any] else { return "(제목 없음)" }
        for (_, value) in properties {
            guard let property = value as? [String: Any],
                  property["type"] as? String == "title",
                  let titleArray = property["title"] as? [[String: Any]] else {
                continue
            }
            let text = titleArray.compactMap { $0["plain_text"] as? String }.joined()
            if !text.isEmpty { return text }
        }
        return "(제목 없음)"
    }
}
