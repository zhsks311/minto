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

    @Test("factory는 dev file store root override를 사용한다")
    func factoryUsesLocalDevRootOverride() throws {
        let root = try temporaryDirectory().appendingPathComponent("override", isDirectory: true)
        let store = SecretStoreFactory.make(environment: [
            SecretStoreFactory.devStoreModeEnvironmentKey: "file",
            SecretStoreFactory.devStoreRootEnvironmentKey: root.path
        ])
        let secret = Data("root-override-secret".utf8)

        #expect(store.save(account: "gpt", data: secret, service: "com.minto.test.root"))
        #expect(store.load(account: "gpt", service: "com.minto.test.root") == secret)

        let storedFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(storedFiles.count == 1)
        #expect(!storedFiles[0].contains("root-override-secret"))
    }

    @Test("기본 backend는 실제 프로세스 env의 dev file store를 따른다")
    func defaultBackendsUseProcessEnvironmentDevStoreWhenEnabled() throws {
        let environment = ProcessInfo.processInfo.environment
        let mode = environment[SecretStoreFactory.devStoreModeEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ["file", "local-file", "local"].contains(mode ?? "") else {
            #expect(SecretStoreFactory.make() is KeychainSecretStore)
            return
        }

        let root = try #require(environment[SecretStoreFactory.devStoreRootEnvironmentKey])
        let rootURL = URL(fileURLWithPath: (root as NSString).expandingTildeInPath, isDirectory: true)
        #expect(SecretStoreFactory.make() is LocalDevSecretStore)

        let token = UUID().uuidString
        let llmAccount = "llm-api-key-gpt-\(token)"
        let llmService = "com.minto.test.llm-api.\(token)"
        let oauthKey = "notion-\(token)"
        let confluenceAccount = "confluence-\(token)"
        let llmBackend = SecretStoreLLMAPIKeyStorageBackend()
        let oauthBackend = SecretStoreOAuthTokenStorageBackend()
        let confluenceBackend = SecretStoreConfluenceTokenStorageBackend()

        #expect(llmBackend.save(account: llmAccount, data: Data("sk-env-smoke".utf8), service: llmService))
        #expect(llmBackend.exists(account: llmAccount, service: llmService))
        #expect(llmBackend.load(account: llmAccount, service: llmService) == Data("sk-env-smoke".utf8))

        oauthBackend.save(key: oauthKey, data: Data(#"{"accessToken":"oauth-env-smoke"}"#.utf8))
        #expect(oauthBackend.exists(key: oauthKey))
        #expect(oauthBackend.load(key: oauthKey) != nil)

        confluenceBackend.save(account: confluenceAccount, data: Data("confluence-env-smoke".utf8))
        #expect(confluenceBackend.exists(account: confluenceAccount))
        #expect(confluenceBackend.load(account: confluenceAccount) == Data("confluence-env-smoke".utf8))

        let storedFiles = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
        let matchingStoredFiles = storedFiles.filter { $0.contains(token) }
        #expect(matchingStoredFiles.count == 3)
        let rootAttributes = try FileManager.default.attributesOfItem(atPath: rootURL.path)
        #expect(rootAttributes[.posixPermissions] as? Int == 0o700)
        for fileName in matchingStoredFiles {
            let filePath = rootURL.appendingPathComponent(fileName).path
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: filePath)
            #expect(fileAttributes[.posixPermissions] as? Int == 0o600)
        }

        #expect(llmBackend.delete(account: llmAccount, service: llmService))
        oauthBackend.delete(key: oauthKey)
        confluenceBackend.delete(account: confluenceAccount)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
        let matchingRemainingFiles = remainingFiles.filter { $0.contains(token) }
        #expect(matchingRemainingFiles.isEmpty)
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
