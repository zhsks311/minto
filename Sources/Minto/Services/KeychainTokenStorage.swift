import Foundation
import MCP

/// OAuthAccessToken을 JSON으로 직렬화해 Keychain에 영속 저장하는 TokenStorage 구현.
///
/// OAuthAuthorizer가 토큰 취득 후 save()를 호출하므로 재실행 시 재인증이 불필요하다.
/// clientID도 OAuthAccessToken에 포함돼 저장되므로, DCR로 발급된 client_id도 함께 유지된다.
final class KeychainTokenStorage: TokenStorage, @unchecked Sendable {
    private let keychainKey: String
    private let lock = NSLock()
    private var cachedToken: OAuthAccessToken??

    init(keychainKey: String) {
        self.keychainKey = keychainKey
    }

    func save(_ token: OAuthAccessToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        lock.withLock {
            cachedToken = .some(token)
        }
        KeychainService.save(provider: keychainKey, data: data)
    }

    func load() -> OAuthAccessToken? {
        if let cached = lock.withLock({ cachedToken }) {
            return cached
        }
        guard let data = KeychainService.load(provider: keychainKey) else {
            lock.withLock {
                cachedToken = .some(nil)
            }
            return nil
        }
        let token = try? JSONDecoder().decode(OAuthAccessToken.self, from: data)
        lock.withLock {
            cachedToken = .some(token)
        }
        return token
    }

    func hasToken() -> Bool {
        if let cached = lock.withLock({ cachedToken }) {
            return cached != nil
        }
        return KeychainService.exists(provider: keychainKey)
    }

    func clear() {
        lock.withLock {
            cachedToken = .some(nil)
        }
        KeychainService.delete(provider: keychainKey)
    }
}
