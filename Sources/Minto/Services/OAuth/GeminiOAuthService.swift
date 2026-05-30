import Foundation
import CryptoKit
import AuthenticationServices
import AppKit

// Google gemini-cli 공개 Desktop OAuth 클라이언트 자격증명.
// Google의 오픈소스 gemini-cli에 하드코딩된 공개 값으로 기밀이 아님 (PKCE가 보안 제공).
// ⚠️ Google ToS 상 third-party 앱에서 이 client를 사용하는 것은 정책 위반.
// 사용자에게 경고 후 동의를 받고 사용해야 함.
private let kClientID = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
private let kClientSecret = "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"
private let kRedirectScheme = "minto"
private let kRedirectURI = "minto://oauth/gemini"
private let kScopes = "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile"
private let kKeychainKey = "gemini"

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

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: kClientID),
            URLQueryItem(name: "redirect_uri", value: kRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: kScopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let authURL = components.url else { throw GeminiOAuthError.badURL }

        let callbackURL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: kRedirectScheme
            ) { url, error in
                if let error { cont.resume(throwing: error) }
                else if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: GeminiOAuthError.noCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw GeminiOAuthError.noCode }

        let tokenResponse = try await exchangeCode(code: code, verifier: verifier)
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

    public func correct(text: String, context: String) async throws -> String {
        let token = try await validAccessToken()
        guard let creds = credentials else { throw GeminiOAuthError.notLoggedIn }

        let prompt = correctionPrompt(text: text, context: context)
        let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("google-api-nodejs-client/9.15.1 (gzip)", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "project": creds.projectId,
            "model": "gemini-2.5-flash",
            "user_prompt_id": UUID().uuidString,
            "request": [
                "contents": [["role": "user", "parts": [["text": prompt]]]],
                "generationConfig": ["maxOutputTokens": 200, "temperature": 0.1]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let candidates = response["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let result = parts.first?["text"] as? String
        else { throw GeminiOAuthError.badResponse }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private helpers

    private func exchangeCode(code: String, verifier: String) async throws -> GeminiCredentials {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type=authorization_code",
            "code=\(code)",
            "code_verifier=\(verifier)",
            "client_id=\(kClientID)",
            "client_secret=\(kClientSecret)",
            "redirect_uri=\(kRedirectURI)"
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
        request.httpBody = try JSONSerialization.data(withJSONObject: ["metadata": [:]])

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let projectId = json["cloudaiCompanionProject"] as? String, !projectId.isEmpty {
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

    private func correctionPrompt(text: String, context: String) -> String {
        """
        당신은 한국어 음성 인식 결과를 교정하는 전문가입니다.

        직전 발화 컨텍스트: \(context)
        현재 인식 결과: \(text)

        규칙:
        - 한국어 띄어쓰기와 문장부호 교정
        - 동음이의어 중 컨텍스트에 맞는 것으로 교정
        - 내용을 추가하거나 삭제하지 말 것
        - 교정된 텍스트만 출력 (설명 없이)

        교정 결과:
        """
    }
}

extension GeminiOAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first ?? NSWindow()
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
    case badURL, noCallback, noCode, notLoggedIn, badResponse

    var errorDescription: String? {
        switch self {
        case .badURL: return "잘못된 URL"
        case .noCallback: return "OAuth 콜백 없음"
        case .noCode: return "인증 코드 없음"
        case .notLoggedIn: return "Gemini 로그인 필요"
        case .badResponse: return "API 응답 파싱 실패"
        }
    }
}
