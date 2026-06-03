import Foundation
import CryptoKit
import AppKit
import Darwin

// Google gemini-cli 공개 Desktop OAuth 클라이언트 자격증명.
// Google의 오픈소스 gemini-cli에 하드코딩된 공개 값으로 기밀이 아님 (PKCE가 보안 제공).
// ⚠️ Google ToS 상 third-party 앱에서 이 client를 사용하는 것은 정책 위반.
// 사용자에게 경고 후 동의를 받고 사용해야 함.
private let kClientID = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
private let kClientSecret = "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"
// gemini-cli 공개 클라이언트는 "데스크톱 앱" 타입이라 loopback 리디렉트만 허용한다 (커스텀 스킴 불가).
private let kRedirectPath = "/oauth2callback"
private let kScopes = "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile"
private let kKeychainKey = "gemini"

// 교정/요약 모델·출력 한도. 모델 상향 시 여기만 바꾼다. 단 Gemini는 무료 등급에서 반복 호출 시 429
// 한도가 잦고, 상위 모델(gemini-2.5-pro)은 thinkingBudget 동작이 달라 검증이 필요 → 상향은 보류.
// max_tokens는 긴 요약 잘림 시 상향. (thinking 모델이라 thinkingBudget=0으로 사고 토큰 소비를 막음.)
private let kGeminiModel = "gemini-2.5-flash"
private let kGeminiMaxOutputTokens = 1024

// MARK: - Token Model

struct GeminiCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAtMs: Int64   // Unix milliseconds
    var email: String
    var projectId: String
    var managedProjectId: String

    var isExpired: Bool {
        Int64(Date().timeIntervalSince1970 * 1000) + 60_000 >= expiresAtMs
    }

    // refresh 필드 packed format: "refreshToken|projectId|managedProjectId"
    var packedRefresh: String {
        guard !projectId.isEmpty else { return refreshToken }
        return "\(refreshToken)|\(projectId)|\(managedProjectId)"
    }

    static func unpack(packed: String, accessToken: String, expiresAtMs: Int64, email: String) -> GeminiCredentials {
        let parts = packed.split(separator: "|", maxSplits: 2).map(String.init)
        return GeminiCredentials(
            accessToken: accessToken,
            refreshToken: parts[0],
            expiresAtMs: expiresAtMs,
            email: email,
            projectId: parts.count > 1 ? parts[1] : "",
            managedProjectId: parts.count > 2 ? parts[2] : ""
        )
    }
}

// MARK: - Service

@MainActor
public final class GeminiOAuthService: NSObject {

    public static let shared = GeminiOAuthService()
    private override init() {}

    /// 설정에서 고른 모델 키 + 목록(설정 UI·서비스 공용). 미설정이면 기본 상수.
    public static let modelDefaultsKey = "geminiModel"
    public static let availableModels: [(id: String, label: String)] = [
        ("gemini-2.5-flash", "2.5-flash · 빠름"),
        ("gemini-2.5-pro", "2.5-pro · 고품질"),
    ]
    static var selectedModel: String {
        let v = UserDefaults.standard.string(forKey: modelDefaultsKey) ?? ""
        return v.isEmpty ? kGeminiModel : v
    }

    // MARK: - Persisted state

    // 메모리 캐시: 바깥 Optional이 "아직 로드 안 함" 여부, 안쪽이 실제 자격증명.
    // SwiftUI body가 매 렌더마다 isLoggedIn을 호출해도 Keychain 접근은 실행당 최초 1회로 제한된다.
    private var cachedCredentials: GeminiCredentials??

    private(set) var credentials: GeminiCredentials? {
        get {
            if let cached = cachedCredentials { return cached }
            let loaded = KeychainService.load(provider: kKeychainKey)
                .flatMap { try? JSONDecoder().decode(GeminiCredentials.self, from: $0) }
            cachedCredentials = .some(loaded)
            return loaded
        }
        set {
            cachedCredentials = .some(newValue)
            if let v = newValue, let data = try? JSONEncoder().encode(v) {
                KeychainService.save(provider: kKeychainKey, data: data)
            } else {
                KeychainService.delete(provider: kKeychainKey)
            }
        }
    }

    public var isLoggedIn: Bool { credentials != nil }
    public var email: String { credentials?.email ?? "" }

    // MARK: - Login (PKCE)

    public func login() async throws {
        let verifier = generateVerifier()
        let challenge = pkceChallenge(for: verifier)
        let state = UUID().uuidString

        // loopback 소켓을 먼저 띄워 포트를 확보한 뒤, 그 포트로 redirect_uri를 구성한다.
        let (serverFD, port) = try Self.makeLoopbackSocket()
        let redirectURI = "http://127.0.0.1:\(port)\(kRedirectPath)"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: kClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: kScopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let authURL = components.url else {
            close(serverFD)
            throw GeminiOAuthError.badURL
        }

        // 시스템 브라우저로 Google 인증 페이지를 연다 (loopback은 ASWebAuthenticationSession으로 못 잡음).
        NSWorkspace.shared.open(authURL)

        // 백그라운드 큐에서 단 한 번의 콜백 연결을 받아 code를 추출한다 (accept는 블로킹이므로 메인 스레드 밖에서).
        let code = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try Self.acceptOAuthCode(serverFD: serverFD, expectedState: state) }
                close(serverFD)
                cont.resume(with: result)
            }
        }

        // redirect_uri는 토큰 교환에서도 인증 요청과 바이트 단위로 동일해야 한다.
        let tokenResponse = try await exchangeCode(code: code, verifier: verifier, redirectURI: redirectURI)
        credentials = tokenResponse
        try await discoverProject()
    }

    public func logout() {
        credentials = nil
    }

    // MARK: - Valid token (auto-refresh)

    public func validAccessToken() async throws -> String {
        guard var creds = credentials else { throw GeminiOAuthError.notLoggedIn }
        if creds.isExpired {
            creds = try await refreshToken(creds: creds)
        }
        return creds.accessToken
    }

    // MARK: - Correction API

    public func correct(instructions: String, userContent: String) async throws -> String {
        let token = try await validAccessToken()
        guard var creds = credentials else { throw GeminiOAuthError.notLoggedIn }

        // 과거 버그(잘못된 키 casing)로 projectId가 비어 저장된 경우, 재로그인 없이 여기서 복구한다.
        if creds.projectId.isEmpty {
            try await discoverProject()
            creds = credentials ?? creds
        }

        // Gemini는 system role을 따로 쓰지 않으므로 instructions + userContent를 단일 user 메시지로 연결한다.
        let prompt = instructions + "\n\n" + userContent
        let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("google-api-nodejs-client/9.15.1 (gzip)", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "project": creds.projectId,
            "model": Self.selectedModel,
            "user_prompt_id": UUID().uuidString,
            "request": [
                "contents": [["role": "user", "parts": [["text": prompt]]]],
                // gemini-2.5-flash는 thinking 모델이라 사고에 출력 토큰을 소비한다.
                // 교정은 추론이 거의 불필요하므로 thinking을 끄고(=0) 출력 한도를 넉넉히 둔다.
                "generationConfig": [
                    "maxOutputTokens": kGeminiMaxOutputTokens,
                    "temperature": 0.1,
                    "thinkingConfig": ["thinkingBudget": 0]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let bodyText = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8>"
            fputs("[Gemini] correct HTTP \(status): \(bodyText)\n", stderr)
            throw GeminiOAuthError.badResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let candidates = response["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let result = parts.first?["text"] as? String
        else {
            let bodyText = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8>"
            fputs("[Gemini] correct parse failed, body: \(bodyText)\n", stderr)
            throw GeminiOAuthError.badResponse
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private helpers

    private func exchangeCode(code: String, verifier: String, redirectURI: String) async throws -> GeminiCredentials {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type=authorization_code",
            "code=\(code)",
            "code_verifier=\(verifier)",
            "client_id=\(kClientID)",
            "client_secret=\(kClientSecret)",
            "redirect_uri=\(redirectURI)"
        ].joined(separator: "&")
        request.httpBody = params.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAtMs = Int64((Date().timeIntervalSince1970 + Double(json.expiresIn ?? 3600)) * 1000)
        let email = try await fetchEmail(token: json.accessToken)
        return GeminiCredentials(
            accessToken: json.accessToken,
            refreshToken: json.refreshToken ?? "",
            expiresAtMs: expiresAtMs,
            email: email,
            projectId: "",
            managedProjectId: ""
        )
    }

    private func refreshToken(creds: GeminiCredentials) async throws -> GeminiCredentials {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type=refresh_token",
            "refresh_token=\(creds.refreshToken)",
            "client_id=\(kClientID)",
            "client_secret=\(kClientSecret)"
        ].joined(separator: "&")
        request.httpBody = params.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAtMs = Int64((Date().timeIntervalSince1970 + Double(json.expiresIn ?? 3600)) * 1000)
        var updated = creds
        updated.accessToken = json.accessToken
        updated.refreshToken = json.refreshToken ?? creds.refreshToken
        updated.expiresAtMs = expiresAtMs
        credentials = updated
        return updated
    }

    private func discoverProject() async throws {
        guard var creds = credentials else { return }
        let token = creds.accessToken
        let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "metadata": ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        // 주의: Google 응답 키는 전부 소문자 "companion" (cloudaicompanionProject). 대문자로 읽으면 nil → 빈 프로젝트.
        if let projectId = json["cloudaicompanionProject"] as? String, !projectId.isEmpty {
            creds.projectId = projectId
            credentials = creds
        }
    }

    private func fetchEmail(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v1/userinfo?alt=json")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["email"] as? String ?? ""
    }

    private func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func pkceChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Loopback OAuth callback server (BSD socket, one-shot)

extension GeminiOAuthService {

    /// 127.0.0.1에 ephemeral 포트로 바인드한 리스닝 소켓을 만들고 (fd, 포트)를 반환한다.
    /// socket/bind/listen/getsockname은 블로킹이 아니므로 호출 스레드에서 바로 실행 가능.
    fileprivate nonisolated static func makeLoopbackSocket() throws -> (fd: Int32, port: UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw GeminiOAuthError.socketError }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0                              // ephemeral 포트
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")  // loopback 전용 바인드

        let bindOK = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0, listen(fd, 1) == 0 else {
            close(fd)
            throw GeminiOAuthError.socketError
        }

        // accept가 영원히 멈추지 않도록 5분 타임아웃을 건다 (사용자가 인증을 끝내지 않는 경우 대비).
        var timeout = timeval(tv_sec: 300, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        return (fd, UInt16(bigEndian: bound.sin_port))
    }

    /// 콜백 연결 1건을 받아 요청 라인에서 code/state를 파싱하고, 브라우저에 완료 페이지를 응답한다.
    /// 블로킹 호출이므로 반드시 백그라운드 큐에서 실행한다.
    fileprivate nonisolated static func acceptOAuthCode(serverFD: Int32, expectedState: String) throws -> String {
        let clientFD = accept(serverFD, nil, nil)
        guard clientFD >= 0 else { throw GeminiOAuthError.noCallback }
        defer { close(clientFD) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let n = read(clientFD, &buffer, buffer.count)
        let request = n > 0 ? String(decoding: buffer[0..<n], as: UTF8.self) : ""

        // 첫 줄: "GET /oauth2callback?code=...&state=... HTTP/1.1"
        let requestLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let items = URLComponents(string: "http://127.0.0.1\(path)")?.queryItems ?? []
        let returnedState = items.first { $0.name == "state" }?.value
        let code = items.first { $0.name == "code" }?.value

        let success = (code != nil) && (returnedState == expectedState)
        let title = success ? "로그인 완료" : "로그인 실패"
        let message = success ? "이 창을 닫고 minto로 돌아가세요." : "다시 시도해 주세요."
        let body = "<!doctype html><html><head><meta charset=\"utf-8\"></head><body style=\"font-family:-apple-system,sans-serif;text-align:center;padding:48px\"><h2>\(title)</h2><p>\(message)</p></body></html>"
        writeHTTPResponse(clientFD, body: body)

        guard returnedState == expectedState else { throw GeminiOAuthError.stateMismatch }
        guard let code else { throw GeminiOAuthError.noCode }
        return code
    }

    /// 완전한 HTTP 응답(상태 라인 + 헤더 + 본문)을 끝까지 써서 브라우저가 에러로 오인하지 않게 한다.
    private nonisolated static func writeHTTPResponse(_ fd: Int32, body: String) {
        let response = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n"
            + body
        let bytes = Array(response.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written <= 0 { break }
            offset += written
        }
    }
}

// MARK: - Supporting Types

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum GeminiOAuthError: Error, LocalizedError {
    case badURL, noCallback, noCode, notLoggedIn, badResponse, socketError, stateMismatch

    var errorDescription: String? {
        switch self {
        case .badURL: return "잘못된 URL"
        case .noCallback: return "OAuth 콜백 없음 (시간 초과)"
        case .noCode: return "인증 코드 없음"
        case .notLoggedIn: return "Gemini 로그인 필요"
        case .badResponse: return "API 응답 파싱 실패"
        case .socketError: return "로컬 콜백 서버를 열 수 없음"
        case .stateMismatch: return "OAuth state 불일치 (보안 검증 실패)"
        }
    }
}
