import Foundation
import MCP

protocol OAuthTokenStorageBackend: Sendable {
    func exists(key: String) -> Bool
    func load(key: String) -> Data?
    func save(key: String, data: Data)
    func delete(key: String)
}

struct KeychainOAuthTokenStorageBackend: OAuthTokenStorageBackend {
    func exists(key: String) -> Bool {
        KeychainService.exists(provider: key)
    }

    func load(key: String) -> Data? {
        KeychainService.load(provider: key)
    }

    func save(key: String, data: Data) {
        KeychainService.save(provider: key, data: data)
    }

    func delete(key: String) {
        KeychainService.delete(provider: key)
    }
}

/// OAuthAccessToken을 JSON으로 직렬화해 Keychain에 영속 저장하는 TokenStorage 구현.
///
/// OAuthAuthorizer가 토큰 취득 후 save()를 호출하므로 재실행 시 재인증이 불필요하다.
/// clientID도 OAuthAccessToken에 포함돼 저장되므로, DCR로 발급된 client_id도 함께 유지된다.
final class KeychainTokenStorage: TokenStorage, @unchecked Sendable {
    private let keychainKey: String
    private let storage: any OAuthTokenStorageBackend
    private let lock = NSLock()
    private var cachedToken: OAuthAccessToken??
    private var storedTokenNeedsReconnect = false

    init(keychainKey: String, storage: any OAuthTokenStorageBackend = KeychainOAuthTokenStorageBackend()) {
        self.keychainKey = keychainKey
        self.storage = storage
    }

    func save(_ token: OAuthAccessToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        lock.withLock {
            cachedToken = .some(token)
            storedTokenNeedsReconnect = false
        }
        storage.save(key: keychainKey, data: data)
    }

    func load() -> OAuthAccessToken? {
        if let cached = lock.withLock({ cachedToken }) {
            return cached
        }
        guard let data = storage.load(key: keychainKey) else {
            lock.withLock {
                cachedToken = .some(nil)
                storedTokenNeedsReconnect = false
            }
            return nil
        }
        let token: OAuthAccessToken?
        do {
            token = try JSONDecoder().decode(OAuthAccessToken.self, from: data)
        } catch {
            token = nil
        }
        lock.withLock {
            cachedToken = .some(token)
            storedTokenNeedsReconnect = (token == nil)
        }
        return token
    }

    func hasToken() -> Bool {
        if lock.withLock({ storedTokenNeedsReconnect }) {
            return false
        }
        if let cached = lock.withLock({ cachedToken }) {
            return cached != nil
        }
        return storage.exists(key: keychainKey)
    }

    var requiresReconnect: Bool {
        lock.withLock { storedTokenNeedsReconnect }
    }

    func markRequiresReconnect() {
        lock.withLock {
            cachedToken = .some(nil)
            storedTokenNeedsReconnect = true
        }
    }

    func clear() {
        lock.withLock {
            cachedToken = .some(nil)
            storedTokenNeedsReconnect = false
        }
        storage.delete(key: keychainKey)
    }
}
