import os
import Foundation
import AppKit

// OpenAI Codex Device Auth Flow.
// ⚠️ chatgpt.com 내부 엔드포인트 사용 — OpenAI ToS 회색 지대.
// 사용자에게 경고 후 동의를 받고 사용해야 함.
private let kClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
private let kKeychainKey = "codex"
private let kSecretStore = SecretStoreFactory.make()

// 교정 모델: 유료(plus/pro/team/…)는 상위 모델, 무료/미상 tier는 경량 기본.
// 무료 계정은 상위 모델 ID가 막혀(4xx) 교정을 통째로 잃을 수 있으므로 보수적으로 기본 모델을 쓰고,
// 유료라도 상위 모델 호출이 실패하면 correct()가 검증된 하위 모델로 순차 폴백한다(아래).
private let kCorrectionModelDefault = "gpt-5.4-mini"
private let kCorrectionModelPaid = "gpt-5.5"
private let kCorrectionFallbackModels = ["gpt-5.4", kCorrectionModelDefault]

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
            let loaded = kSecretStore.load(account: kKeychainKey, service: KeychainService.oauthService)
                .flatMap { try? JSONDecoder().decode(CodexCredentials.self, from: $0) }
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
                Log.oauth.error("Codex login failed: \(error.localizedDescription, privacy: .public)")
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

    public func correct(instructions: String, userContent: String, maxOutputTokens: Int? = nil) async throws -> String {
        guard var creds = credentials else { throw CodexError.notLoggedIn }
        if creds.isExpired {
            creds = try await refreshToken(creds: creds)
        }

        // tier(plan)에 따라 모델 결정. 유료 상위 모델이 거부/오류면 기본(mini)로 1회 폴백해
        // "상위 모델 ID가 틀려서 교정을 통째로 잃는" 일을 막는다. 429(rate limit)는 mini도
        // 동일하게 막힐 가능성이 커 폴백하지 않고 그대로 던진다(무한 시도 방지).
        let plan = chatGPTPlanType(from: creds.accessToken)
        let primaryModel = correctionModel(for: plan)
        let modelChain = correctionModelFallbackChain(for: primaryModel)
        for (index, model) in modelChain.enumerated() {
            do {
                return try await performCorrection(
                    model: model,
                    instructions: instructions,
                    userContent: userContent,
                    maxOutputTokens: maxOutputTokens,
                    creds: creds
                )
            } catch let error as CodexError where index < modelChain.count - 1 && error.isModelFallbackable {
                let fallback = modelChain[index + 1]
                Log.oauth.info("Codex model '\(model, privacy: .public)' 실패(plan=\(plan ?? "?", privacy: .public)) → '\(fallback, privacy: .public)'로 폴백")
                continue
            }
        }
        throw CodexError.badResponse
    }

    /// 설정에서 고른 모델 키(설정 UI·서비스 공용).
    nonisolated public static let modelDefaultsKey = "codexModel"
    nonisolated public static let defaultModelID = "auto"

    /// 설정 Picker용 모델 목록. "auto"는 플랜(tier)에 맞춰 자동 선택.
    public static let availableModels: [(id: String, label: String)] = [
        ("auto", "자동 (플랜에 맞춤)"),
        ("gpt-5.5", "gpt-5.5 · 최신 고품질"),
        ("gpt-5.3-codex", "gpt-5.3-codex · 코딩 특화"),
        ("gpt-5.4", "gpt-5.4 · 균형"),
        ("gpt-5.4-mini", "gpt-5.4-mini · 빠름"),
    ]

    /// 사용할 교정 모델. 설정에서 명시 선택했으면 그 값, "auto"/미설정이면 plan(tier)에 맞춘다.
    /// 무료(free)·미상 → 경량 기본, 유료(plus/pro/team/…) → 상위.
    func correctionModel(for plan: String?) -> String {
        let chosen = UserDefaults.standard.string(forKey: Self.modelDefaultsKey) ?? Self.defaultModelID
        if chosen != Self.defaultModelID, !chosen.isEmpty {
            return chosen
        }
        switch plan?.lowercased() {
        case .none, .some(""), .some("free"), .some("chatgptfree"):
            return kCorrectionModelDefault
        default:
            return kCorrectionModelPaid
        }
    }

    func correctionModelFallbackChain(for model: String) -> [String] {
        let candidates: [String]
        switch model {
        case kCorrectionModelDefault:
            candidates = [model]
        case "gpt-5.4":
            candidates = [model, kCorrectionModelDefault]
        case kCorrectionModelPaid:
            candidates = [model] + kCorrectionFallbackModels
        default:
            candidates = [model, kCorrectionModelDefault]
        }
        return candidates.reduce(into: [String]()) { result, candidate in
            if !candidate.isEmpty, !result.contains(candidate) {
                result.append(candidate)
            }
        }
    }

    private func performCorrection(
        model: String,
        instructions: String,
        userContent: String,
        maxOutputTokens: Int?,
        creds: CodexCredentials
    ) async throws -> String {
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

        var body: [String: Any] = [
            "model": model,
            "stream": true,   // Codex 백엔드는 SSE 스트리밍을 강제
            "store": false,   // 서버측 대화 저장 비활성화를 강제
            "instructions": instructions,  // Codex Responses API는 instructions 필수
            "input": [["role": "user", "content": userContent]]
        ]
        if let maxOutputTokens {
            body["max_output_tokens"] = max(1, maxOutputTokens)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var errData = Data()
            for try await byte in bytes {
                errData.append(byte)
                if errData.count >= 800 { break }
            }
            Log.oauth.error("Codex correct HTTP \(status, privacy: .public) model=\(model, privacy: .public) bodyLen=\(errData.count, privacy: .public)")
            // 무료 tier·미인가·모델 미허용은 4xx로 온다(상위 모델→mini 폴백 대상). 429는 rate limit(폴백 무의미).
            switch status {
            case 429:
                throw CodexError.rateLimited
            case 400, 401, 403, 404:
                throw CodexError.notEntitled
            default:
                throw CodexError.badResponse
            }
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
            Log.oauth.info("Codex \(step, privacy: .public) HTTP 200")
        } else {
            Log.oauth.error("Codex \(step, privacy: .public) HTTP \(status, privacy: .public) bodyLen=\(data.count, privacy: .public)")
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

    /// access token(JWT)의 `chatgpt_plan_type` 클레임을 추출한다(free/plus/pro/team/enterprise 등).
    /// 무료/유료 구분에 쓴다. 클레임이 없으면 nil → correctionModel이 보수적 기본 모델을 택한다.
    func chatGPTPlanType(from accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)  // base64url 패딩
        guard let data = Data(base64Encoded: payload
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any],
              let plan = auth["chatgpt_plan_type"] as? String
        else { return nil }
        return plan
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
}

enum CodexError: Error, LocalizedError {
    case notLoggedIn, badResponse, timeout, notEntitled, rateLimited

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "OpenAI Codex 로그인 필요"
        case .badResponse: return "Codex API 응답 파싱 실패"
        case .timeout: return "인증 시간 초과 — 다시 시도하세요"
        case .notEntitled: return "현재 OpenAI 플랜에서 이 모델을 쓸 수 없어요"
        case .rateLimited: return "OpenAI 호출 한도 초과 — 잠시 후 다시 시도하세요"
        }
    }

    /// 상위 모델 호출 실패 시 기본(mini) 모델로 폴백해도 되는 오류인지.
    /// rate limit(429)은 mini도 동일하게 막힐 가능성이 커 폴백 대상이 아니다.
    var isModelFallbackable: Bool {
        switch self {
        case .notEntitled, .badResponse: return true
        case .rateLimited, .notLoggedIn, .timeout: return false
        }
    }
}
