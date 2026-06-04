import Foundation
import MCP

/// OAuthAccessToken을 JSON으로 직렬화해 Keychain에 영속 저장하는 TokenStorage 구현.
///
/// OAuthAuthorizer가 토큰 취득 후 save()를 호출하므로 재실행 시 재인증이 불필요하다.
/// clientID도 OAuthAccessToken에 포함돼 저장되므로, DCR로 발급된 client_id도 함께 유지된다.
final class KeychainTokenStorage: TokenStorage, @unchecked Sendable {
    private let keychainKey: String

    init(keychainKey: String) {
        self.keychainKey = keychainKey
    }

    func save(_ token: OAuthAccessToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        KeychainService.save(provider: keychainKey, data: data)
    }

    func load() -> OAuthAccessToken? {
        guard let data = KeychainService.load(provider: keychainKey) else { return nil }
        return try? JSONDecoder().decode(OAuthAccessToken.self, from: data)
    }

    func clear() {
        KeychainService.delete(provider: keychainKey)
    }
}
