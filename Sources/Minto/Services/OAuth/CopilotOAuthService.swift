import os
import Foundation
import AppKit

// GitHub OAuth Device Code Flow — Copilot CLI 공식 client ID 사용 (합법).
// gho_ 토큰 → copilot_internal/v2/token 교환 → 단기 Copilot API 토큰.
private let kClientID = "Ov23li8tweQw6odWQebz"
private let kKeychainKey = "copilot"
private let kSecretStore = SecretStoreFactory.make()

// 교정/요약 모델·출력 한도. Copilot은 계정/조직 정책에 따라 모델 노출이 달라질 수 있다.
// 기본값은 일반 Copilot Chat에서 널리 쓰이는 경량 GPT 모델로 둔다.
private let kCopilotModel = "gpt-5-mini"
private let kCopilotMaxTokens = 1024

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

    /// 설정에서 고른 모델 키 + 목록. 미설정이면 기본 상수.
    nonisolated public static let modelDefaultsKey = "copilotModel"
    nonisolated public static let defaultModelID = kCopilotModel
    public static let availableModels: [(id: String, label: String)] = [
        ("gpt-5-mini", "GPT-5 mini · 기본"),
        ("gpt-5.3-codex", "GPT-5.3-Codex · 코딩"),
        ("gpt-5.4-mini", "GPT-5.4 mini · 빠름"),
        ("gpt-5.4-nano", "GPT-5.4 nano · 저지연"),
        ("gpt-5.4", "GPT-5.4 · 균형"),
        ("gpt-5.5", "GPT-5.5 · 고품질"),
        ("claude-sonnet-4.5", "Claude Sonnet 4.5"),
        ("claude-sonnet-4.6", "Claude Sonnet 4.6"),
        ("claude-haiku-4.5", "Claude Haiku 4.5"),
        ("claude-opus-4.5", "Claude Opus 4.5"),
        ("claude-opus-4.6", "Claude Opus 4.6"),
        ("claude-opus-4.7", "Claude Opus 4.7"),
        ("claude-opus-4.8", "Claude Opus 4.8"),
        ("gemini-3-flash", "Gemini 3 Flash"),
        ("gemini-3.1-pro-preview", "Gemini 3.1 Pro Preview"),
        ("gemini-3.5-flash", "Gemini 3.5 Flash"),
        ("gemini-2.5-pro", "Gemini 2.5 Pro"),
        ("mai-code-1-flash", "MAI-Code-1-Flash"),
        ("raptor-mini", "Raptor mini"),
    ]
    static var selectedModel: String {
        let v = UserDefaults.standard.string(forKey: modelDefaultsKey) ?? ""
        return v.isEmpty ? kCopilotModel : v
    }

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
            let loaded = kSecretStore.load(account: kKeychainKey, service: KeychainService.oauthService)
                .flatMap { try? JSONDecoder().decode(CopilotCredentials.self, from: $0) }
            cachedCredentials = .some(loaded)
            return loaded
        }
        set {
            objectWillChange.send()  // isLoggedIn은 computed이므로 자격증명 변경 시 직접 뷰에 알린다
            cachedCredentials = .some(newValue)
            if let v = newValue, let data = try? JSONEncoder().encode(v) {
                _ = kSecretStore.save(account: kKeychainKey, data: data, service: KeychainService.oauthService)
            } else {
                _ = kSecretStore.delete(account: kKeychainKey, service: KeychainService.oauthService)
            }
        }
    }

    public var isLoggedIn: Bool {
        if let cached = cachedCredentials {
            return cached != nil
        }
        return kSecretStore.exists(account: kKeychainKey, service: KeychainService.oauthService)
    }

    public var email: String {
        if case .some(.some(let credentials)) = cachedCredentials {
            return credentials.email
        }
        return ""
    }

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

    public func correct(instructions: String, userContent: String) async throws -> String {
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

        // 교정 규칙(instructions)은 system 메시지로, 가변 입력(userContent)은 user 메시지로 분리.
        let body: [String: Any] = [
            "model": Self.selectedModel,
            "max_tokens": kCopilotMaxTokens,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": userContent]
            ]
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

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // 성공 본문엔 토큰이 있어 로그하지 않고, 실패 시에도 body 길이만 남긴다.
            Log.oauth.error("Copilot token-exchange HTTP \(status, privacy: .public) bodyLen=\(data.count, privacy: .public)")
            // GitHub은 Copilot 구독이 없는 계정에 이 내부 엔드포인트를 404(또는 403)로 숨긴다.
            if status == 404 || status == 403 {
                throw CopilotError.noSubscription
            }
            throw CopilotError.badResponse
        }
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
}

enum CopilotError: Error, LocalizedError {
    case notLoggedIn, badResponse, tokenExpired, noSubscription

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "GitHub Copilot 로그인 필요"
        case .badResponse: return "Copilot API 응답 파싱 실패"
        case .tokenExpired: return "Device code 만료 — 다시 시도하세요"
        case .noSubscription: return "이 GitHub 계정에 활성 Copilot 구독이 없습니다. Copilot 구독이 있는 계정으로 로그인하세요."
        }
    }
}
