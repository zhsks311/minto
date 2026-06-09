import Foundation
import Testing
@testable import MintoCore

@Suite("SecretStore")
struct SecretStoreTests {
    @Test("factory는 opt-in 환경변수에서 file store를 선택한다")
    func factorySelectsLocalDevStoreForOptInEnvironment() {
        let store = SecretStoreFactory.make(environment: [
            SecretStoreFactory.devStoreModeEnvironmentKey: "file"
        ])

        #expect(store is LocalDevSecretStore)
        #expect(SecretStoreFactory.make(environment: [:]) is KeychainSecretStore)
    }

    @Test("LocalDevSecretStore는 secret을 파일에 저장하고 삭제한다")
    func localDevSecretStoreRoundTripsData() throws {
        let root = try temporaryDirectory()
        let store = LocalDevSecretStore(rootDirectory: root)
        let secret = Data("dev-secret-value".utf8)

        #expect(!store.exists(account: "llm-api-key-gpt", service: "com.minto.test"))
        #expect(store.save(account: "llm-api-key-gpt", data: secret, service: "com.minto.test"))
        #expect(store.exists(account: "llm-api-key-gpt", service: "com.minto.test"))
        #expect(store.load(account: "llm-api-key-gpt", service: "com.minto.test") == secret)

        let storedFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(storedFiles.count == 1)
        #expect(!storedFiles[0].contains("dev-secret-value"))
        let rootAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        #expect(rootAttributes[.posixPermissions] as? Int == 0o700)
        let filePath = root.appendingPathComponent(storedFiles[0]).path
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: filePath)
        #expect(fileAttributes[.posixPermissions] as? Int == 0o600)

        #expect(store.delete(account: "llm-api-key-gpt", service: "com.minto.test"))
        #expect(!store.exists(account: "llm-api-key-gpt", service: "com.minto.test"))
        #expect(store.load(account: "llm-api-key-gpt", service: "com.minto.test") == nil)
    }

    @Test("LLM API key store는 injected SecretStore backend로 Keychain 없이 동작한다")
    func llmAPIKeyStoreUsesInjectedSecretStoreBackend() throws {
        let root = try temporaryDirectory()
        let secretStore = LocalDevSecretStore(rootDirectory: root)
        let backend = SecretStoreLLMAPIKeyStorageBackend(secretStore: secretStore)
        let store = LLMAPIKeyStore(serviceName: "com.minto.test.llm-api", storage: backend)

        #expect(!store.hasAPIKey(for: .gpt))
        #expect(store.saveAPIKey("sk-test", for: .gpt))
        #expect(store.hasAPIKey(for: .gpt))
        #expect(store.apiKey(for: .gpt) == "sk-test")
        #expect(store.deleteAPIKey(for: .gpt))
        #expect(!store.hasAPIKey(for: .gpt))
    }

    @Test("Confluence token backend는 injected SecretStore로 token 존재와 원문 load를 분리한다")
    func confluenceTokenBackendUsesInjectedSecretStore() throws {
        let root = try temporaryDirectory()
        let secretStore = LocalDevSecretStore(rootDirectory: root)
        let backend = SecretStoreConfluenceTokenStorageBackend(secretStore: secretStore)
        let token = Data("confluence-token".utf8)

        #expect(!backend.exists(account: "confluence"))
        backend.save(account: "confluence", data: token)
        #expect(backend.exists(account: "confluence"))
        #expect(backend.load(account: "confluence") == token)
        backend.delete(account: "confluence")
        #expect(!backend.exists(account: "confluence"))
    }

    @Test("OAuth token backend는 injected SecretStore로 save/load/delete를 수행한다")
    func oauthTokenBackendUsesInjectedSecretStore() throws {
        let root = try temporaryDirectory()
        let secretStore = LocalDevSecretStore(rootDirectory: root)
        let backend = SecretStoreOAuthTokenStorageBackend(secretStore: secretStore)
        let token = Data(#"{"accessToken":"token"}"#.utf8)

        #expect(!backend.exists(key: "notion"))
        backend.save(key: "notion", data: token)
        #expect(backend.exists(key: "notion"))
        #expect(backend.load(key: "notion") == token)
        backend.delete(key: "notion")
        #expect(!backend.exists(key: "notion"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-secret-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
