import Foundation
import AppKit

// GitHub OAuth Device Code Flow — Copilot CLI 공식 client ID 사용 (합법).
// gho_ 토큰 → copilot_internal/v2/token 교환 → 단기 Copilot API 토큰.
private let kClientID = "Ov23li8tweQw6odWQebz"
private let kKeychainKey = "copilot"

// MARK: - Token Model

struct CopilotCredentials: Codable {
    var githubToken: String   // gho_xxx
    var copilotToken: String  // 단기 Bearer token
    var copilotExpiresAt: TimeInterval
    var email: String

    var isCopilotTokenExpired: Bool {
        Date().timeIntervalSince1970 > copilotExpiresAt - 120
    }
}

// MARK: - Service

@MainActor
public final class CopilotOAuthService: ObservableObject {

    public static let shared = CopilotOAuthService()
    private init() {}

    // 진행 중인 Device Code 흐름 상태
    @Published public var deviceCode: String = ""
    @Published public var isPolling: Bool = false

    private var pollTask: Task<Void, Never>?

    // 메모리 캐시: 바깥 Optional이 "아직 로드 안 함" 여부, 안쪽이 실제 자격증명.
    // SwiftUI body가 매 렌더마다 isLoggedIn을 호출해도 Keychain 접근은 실행당 최초 1회로 제한된다.
    private var cachedCredentials: CopilotCredentials??

    private(set) var credentials: CopilotCredentials? {
        get {
            if let cached = cachedCredentials { return cached }
            let loaded = KeychainService.load(provider: kKeychainKey)
                .flatMap { try? JSONDecoder().decode(CopilotCredentials.self, from: $0) }
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
    public var email: String { credentials?.email ?? "" }

    // MARK: - Login

    /// Device Code flow 시작. UI에 user_code를 표시하고 브라우저를 연다.
    /// 콜백 없이 백그라운드에서 폴링 완료 시 credentials가 설정됨.
    public func startLogin(onComplete: @escaping (Result<Void, Error>) -> Void) {
        pollTask?.cancel()

        Task {
            do {
                let step1 = try await requestDeviceCode()
                deviceCode = step1.userCode
                isPolling = true

                NSWorkspace.shared.open(URL(string: step1.verificationUri)!)

                let token = try await pollForToken(
                    deviceCode: step1.deviceCode,
                    interval: step1.interval
                )
                deviceCode = ""
                isPolling = false

                let copilot = try await exchangeCopilotToken(rawToken: token)
                let email = try await fetchGitHubEmail(token: token)
                credentials = CopilotCredentials(
                    githubToken: token,
                    copilotToken: copilot.token,
                    copilotExpiresAt: copilot.expiresAt,
                    email: email
                )
                onComplete(.success(()))
            } catch {
                deviceCode = ""
                isPolling = false
                onComplete(.failure(error))
            }
        }
    }

    public func cancelLogin() {
        pollTask?.cancel()
        deviceCode = ""
        isPolling = false
    }

    public func logout() {
        credentials = nil
    }

    // MARK: - Correction API

    public func correct(text: String, context: String) async throws -> String {
        guard var creds = credentials else { throw CopilotError.notLoggedIn }

        if creds.isCopilotTokenExpired {
            let refreshed = try await exchangeCopilotToken(rawToken: creds.githubToken)
            creds.copilotToken = refreshed.token
            creds.copilotExpiresAt = refreshed.expiresAt
            credentials = creds
        }

        let url = URL(string: "https://api.githubcopilot.com/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(creds.copilotToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("vscode/1.104.1", forHTTPHeaderField: "Editor-Version")
        request.setValue("HermesAgent/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
        request.setValue("conversation-edits", forHTTPHeaderField: "Openai-Intent")

        let prompt = correctionPrompt(text: text, context: context)
        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 200,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw CopilotError.badResponse }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private struct DeviceCodeResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case interval
        }
    }

    private struct CopilotTokenResponse: Decodable {
        let token: String
        let expiresAt: TimeInterval

        enum CodingKeys: String, CodingKey {
            case token
            case expiresAt = "expires_at"
        }
    }

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "client_id=\(kClientID)&scope=read%3Auser".data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    private func pollForToken(deviceCode: String, interval: Int) async throws -> String {
        let pollInterval = UInt64(max(interval + 3, 8)) * 1_000_000_000
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: pollInterval)
            guard !Task.isCancelled else { throw CancellationError() }

            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "client_id=\(kClientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            request.httpBody = body.data(using: .utf8)

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let token = json["access_token"] as? String { return token }
            if let error = json["error"] as? String, error == "expired_token" {
                throw CopilotError.tokenExpired
            }
        }
        throw CancellationError()
    }

    private func exchangeCopilotToken(rawToken: String) async throws -> CopilotTokenResponse {
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!)
        request.httpMethod = "GET"
        request.setValue("token \(rawToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("vscode/1.104.1", forHTTPHeaderField: "Editor-Version")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(CopilotTokenResponse.self, from: data)
    }

    private func fetchGitHubEmail(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["email"] as? String ?? json?["login"] as? String ?? ""
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

enum CopilotError: Error, LocalizedError {
    case notLoggedIn, badResponse, tokenExpired

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "GitHub Copilot 로그인 필요"
        case .badResponse: return "Copilot API 응답 파싱 실패"
        case .tokenExpired: return "Device code 만료 — 다시 시도하세요"
        }
    }
}
