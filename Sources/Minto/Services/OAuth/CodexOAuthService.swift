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

    // 메모리 캐시: 바깥 Optional이 "아직 로드 안 함" 여부, 안쪽이 실제 자격증명.
    // SwiftUI body가 매 렌더마다 isLoggedIn을 호출해도 Keychain 접근은 실행당 최초 1회로 제한된다.
    private var cachedCredentials: CodexCredentials??

    private(set) var credentials: CodexCredentials? {
        get {
            if let cached = cachedCredentials { return cached }
            let loaded = KeychainService.load(provider: kKeychainKey)
                .flatMap { try? JSONDecoder().decode(CodexCredentials.self, from: $0) }
            cachedCredentials = .some(loaded)
            return loaded
        }
        set {
            objectWillChange.send()  // isLoggedIn은 computed이므로 자격증명 변경 시 직접 뷰에 알린다
            cachedCredentials = .some(newValue)
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
                fputs("[Codex] login failed: \(error)\n", stderr)
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

        // base_url(.../codex) + "/responses" — codex-rs CLI와 동일 경로 (/v1 없음)
        let url = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Cloudflare가 codex 엔드포인트 앞에서 first-party originator만 통과시키므로 codex-rs CLI로 위장한다
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("codex_cli_rs/0.0.0 (minto)", forHTTPHeaderField: "User-Agent")
        if let accountId = chatGPTAccountId(from: creds.accessToken) {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let userContent = "직전 발화 컨텍스트: \(context)\n현재 인식 결과: \(text)"
        let body: [String: Any] = [
            "model": "gpt-5.4-mini",
            "stream": true,   // Codex 백엔드는 SSE 스트리밍을 강제
            "store": false,   // 서버측 대화 저장 비활성화를 강제
            "instructions": correctionInstructions,  // Codex Responses API는 instructions 필수
            "input": [["role": "user", "content": userContent]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var errData = Data()
            for try await byte in bytes {
                errData.append(byte)
                if errData.count >= 800 { break }
            }
            fputs("[Codex] correct HTTP \(status): \(String(data: errData, encoding: .utf8) ?? "")\n", stderr)
            throw CodexError.badResponse
        }

        // SSE 스트림에서 response.output_text.delta 이벤트의 delta를 누적한다 (reasoning delta는 제외)
        var result = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if event["type"] as? String == "response.output_text.delta",
               let delta = event["delta"] as? String {
                result += delta
            }
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CodexError.badResponse }
        return trimmed
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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            userCode = try container.decode(String.self, forKey: .userCode)
            deviceAuthId = try container.decode(String.self, forKey: .deviceAuthId)
            // 서버는 interval을 문자열("5")로 보내기도, 숫자(5)로 보내기도 한다 — 양쪽 모두 허용
            if let intValue = try? container.decode(Int.self, forKey: .interval) {
                interval = intValue
            } else if let stringValue = try? container.decode(String.self, forKey: .interval),
                      let parsed = Int(stringValue) {
                interval = parsed
            } else {
                interval = 5
            }
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

        let (data, response) = try await URLSession.shared.data(for: request)
        logResponse("usercode", response: response, data: data)
        return try JSONDecoder().decode(UserCodeResponse.self, from: data)
    }

    private func logResponse(_ step: String, response: URLResponse, data: Data) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 200 본문에는 토큰·authorization_code 등 자격증명이 들어있어 본문을 남기지 않는다.
        // 에러(비-200)일 때만 본문을 기록해 원인 진단에 쓴다.
        if status == 200 {
            fputs("[Codex] \(step) HTTP 200\n", stderr)
        } else {
            let body = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8>"
            fputs("[Codex] \(step) HTTP \(status): \(body)\n", stderr)
        }
    }

    // access token(JWT)의 `https://api.openai.com/auth.chatgpt_account_id` 클레임을 추출한다.
    private func chatGPTAccountId(from accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)  // base64url 패딩
        guard let data = Data(base64Encoded: payload
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any],
              let accountId = auth["chatgpt_account_id"] as? String
        else { return nil }
        return accountId
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
            logResponse("poll", response: response, data: data)

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

        let (data, response) = try await URLSession.shared.data(for: request)
        logResponse("token-exchange", response: response, data: data)
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

    private let correctionInstructions = """
        당신은 한국어 음성 인식 결과를 교정하는 전문가입니다.
        입력으로 직전 발화 컨텍스트와 현재 인식 결과가 주어집니다.

        규칙:
        - 한국어 띄어쓰기와 문장부호 교정
        - 동음이의어 중 컨텍스트에 맞는 것으로 교정
        - 내용을 추가하거나 삭제하지 말 것
        - 교정된 텍스트만 출력 (설명 없이)
        """
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
