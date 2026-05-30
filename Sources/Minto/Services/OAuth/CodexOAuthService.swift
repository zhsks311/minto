import Foundation
import AppKit

// OpenAI Codex Device Auth Flow.
// ⚠️ chatgpt.com 내부 엔드포인트 사용 — OpenAI ToS 회색 지대.
// 사용자에게 경고 후 동의를 받고 사용해야 함.
private let kClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
private let kKeychainKey = "codex"

// MARK: - Token Model

struct CodexCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: TimeInterval

    var isExpired: Bool {
        Date().timeIntervalSince1970 > expiresAt - 60
    }
}

// MARK: - Service

@MainActor
public final class CodexOAuthService: ObservableObject {

    public static let shared = CodexOAuthService()
    private init() {}

    @Published public var deviceCode: String = ""
    @Published public var isPolling: Bool = false

    private(set) var credentials: CodexCredentials? {
        get {
            guard let data = KeychainService.load(provider: kKeychainKey) else { return nil }
            return try? JSONDecoder().decode(CodexCredentials.self, from: data)
        }
        set {
            if let v = newValue, let data = try? JSONEncoder().encode(v) {
                KeychainService.save(provider: kKeychainKey, data: data)
            } else {
                KeychainService.delete(provider: kKeychainKey)
            }
        }
    }

    public var isLoggedIn: Bool { credentials != nil }

    // MARK: - Login

    public func startLogin(onComplete: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                let step1 = try await requestUserCode()
                deviceCode = step1.userCode
                isPolling = true

                NSWorkspace.shared.open(URL(string: "https://auth.openai.com/codex/device")!)

                let (authCode, codeVerifier) = try await pollForAuthCode(
                    deviceAuthId: step1.deviceAuthId,
                    userCode: step1.userCode,
                    interval: step1.interval
                )
                deviceCode = ""
                isPolling = false

                let tokens = try await exchangeTokens(authCode: authCode, codeVerifier: codeVerifier)
                credentials = tokens
                onComplete(.success(()))
            } catch {
                deviceCode = ""
                isPolling = false
                onComplete(.failure(error))
            }
        }
    }

    public func cancelLogin() {
        deviceCode = ""
        isPolling = false
    }

    public func logout() {
        credentials = nil
    }

    // MARK: - Correction API

    public func correct(text: String, context: String) async throws -> String {
        guard var creds = credentials else { throw CodexError.notLoggedIn }
        if creds.isExpired {
            creds = try await refreshToken(creds: creds)
        }

        let url = URL(string: "https://chatgpt.com/backend-api/codex/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = correctionPrompt(text: text, context: context)
        let body: [String: Any] = [
            "model": "o4-mini",
            "stream": false,
            "input": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [[String: Any]],
              let content = output.first?["content"] as? [[String: Any]],
              let result = content.first?["text"] as? String
        else { throw CodexError.badResponse }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private struct UserCodeResponse: Decodable {
        let userCode: String
        let deviceAuthId: String
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case userCode = "user_code"
            case deviceAuthId = "device_auth_id"
            case interval
        }
    }

    private struct AuthCodeResponse: Decodable {
        let authorizationCode: String
        let codeVerifier: String

        enum CodingKeys: String, CodingKey {
            case authorizationCode = "authorization_code"
            case codeVerifier = "code_verifier"
        }
    }

    private struct TokensResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private func requestUserCode() async throws -> UserCodeResponse {
        let url = URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": kClientID])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(UserCodeResponse.self, from: data)
    }

    private func pollForAuthCode(
        deviceAuthId: String,
        userCode: String,
        interval: Int
    ) async throws -> (String, String) {
        let pollInterval = UInt64(max(interval, 5)) * 1_000_000_000
        let deadline = Date().addingTimeInterval(15 * 60)

        while Date() < deadline && !Task.isCancelled {
            try await Task.sleep(nanoseconds: pollInterval)
            guard !Task.isCancelled else { throw CancellationError() }

            let url = URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["device_auth_id": deviceAuthId, "user_code": userCode]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                let result = try JSONDecoder().decode(AuthCodeResponse.self, from: data)
                return (result.authorizationCode, result.codeVerifier)
            }
        }
        throw CodexError.timeout
    }

    private func exchangeTokens(authCode: String, codeVerifier: String) async throws -> CodexCredentials {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type=authorization_code",
            "code=\(authCode)",
            "code_verifier=\(codeVerifier)",
            "client_id=\(kClientID)",
            "redirect_uri=https://auth.openai.com/deviceauth/callback"
        ].joined(separator: "&")
        request.httpBody = params.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(TokensResponse.self, from: data)
        let expiresAt = Date().timeIntervalSince1970 + Double(resp.expiresIn ?? 3600)
        return CodexCredentials(accessToken: resp.accessToken, refreshToken: resp.refreshToken, expiresAt: expiresAt)
    }

    private func refreshToken(creds: CodexCredentials) async throws -> CodexCredentials {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type=refresh_token",
            "refresh_token=\(creds.refreshToken)",
            "client_id=\(kClientID)"
        ].joined(separator: "&")
        request.httpBody = params.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(TokensResponse.self, from: data)
        let expiresAt = Date().timeIntervalSince1970 + Double(resp.expiresIn ?? 3600)
        let updated = CodexCredentials(accessToken: resp.accessToken, refreshToken: resp.refreshToken, expiresAt: expiresAt)
        credentials = updated
        return updated
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

enum CodexError: Error, LocalizedError {
    case notLoggedIn, badResponse, timeout

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "OpenAI Codex 로그인 필요"
        case .badResponse: return "Codex API 응답 파싱 실패"
        case .timeout: return "인증 시간 초과 — 다시 시도하세요"
        }
    }
}
