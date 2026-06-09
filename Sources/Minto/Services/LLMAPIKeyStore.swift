import Foundation

extension Notification.Name {
    public static let llmAPIKeyStoreDidChange = Notification.Name("minto.llmAPIKeyStoreDidChange")
}

protocol LLMAPIKeyStorageBackend: Sendable {
    func exists(account: String, service: String) -> Bool
    func load(account: String, service: String) -> Data?
    func save(account: String, data: Data, service: String) -> Bool
    func delete(account: String, service: String) -> Bool
}

struct SecretStoreLLMAPIKeyStorageBackend: LLMAPIKeyStorageBackend {
    private let secretStore: any SecretStore

    init(secretStore: any SecretStore = SecretStoreFactory.make()) {
        self.secretStore = secretStore
    }

    func exists(account: String, service: String) -> Bool {
        secretStore.exists(account: account, service: service)
    }

    func load(account: String, service: String) -> Data? {
        secretStore.load(account: account, service: service)
    }

    func save(account: String, data: Data, service: String) -> Bool {
        secretStore.save(account: account, data: data, service: service)
    }

    func delete(account: String, service: String) -> Bool {
        secretStore.delete(account: account, service: service)
    }
}

public protocol LLMAPIKeyProviding: Sendable {
    func apiKey(for providerID: LLMProviderID) -> String?
    func hasAPIKey(for providerID: LLMProviderID) -> Bool
}

public final class LLMAPIKeyStore: LLMAPIKeyProviding, @unchecked Sendable {
    public static let shared = LLMAPIKeyStore()

    private let serviceName: String
    private let storage: any LLMAPIKeyStorageBackend
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var loadedProviderIDs: Set<LLMProviderID> = []
    private var knownProviderStatus: [LLMProviderID: Bool] = [:]
    private var cachedKeys: [LLMProviderID: String] = [:]

    public init(serviceName: String = KeychainService.llmAPIService) {
        self.serviceName = serviceName
        self.storage = SecretStoreLLMAPIKeyStorageBackend()
        self.notificationCenter = .default
    }

    init(
        serviceName: String = KeychainService.llmAPIService,
        storage: any LLMAPIKeyStorageBackend,
        notificationCenter: NotificationCenter = .default
    ) {
        self.serviceName = serviceName
        self.storage = storage
        self.notificationCenter = notificationCenter
    }

    public func apiKey(for providerID: LLMProviderID) -> String? {
        if let cached = lock.withLock({ loadedProviderIDs.contains(providerID) ? cachedKeys[providerID] : nil }) {
            return cached
        }
        if lock.withLock({ loadedProviderIDs.contains(providerID) }) {
            return nil
        }

        let key = storage.load(account: keychainAccount(for: providerID), service: serviceName)
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        lock.withLock {
            loadedProviderIDs.insert(providerID)
            knownProviderStatus[providerID] = (key != nil)
            if let key {
                cachedKeys[providerID] = key
            } else {
                cachedKeys.removeValue(forKey: providerID)
            }
        }
        return key
    }

    public func hasAPIKey(for providerID: LLMProviderID) -> Bool {
        if let cached = lock.withLock({ () -> Bool? in
            if loadedProviderIDs.contains(providerID) {
                return cachedKeys[providerID] != nil
            }
            return knownProviderStatus[providerID]
        }) {
            return cached
        }

        let exists = storage.exists(account: keychainAccount(for: providerID), service: serviceName)
        lock.withLock {
            knownProviderStatus[providerID] = exists
            if !exists {
                loadedProviderIDs.insert(providerID)
                cachedKeys.removeValue(forKey: providerID)
            }
        }
        return exists
    }

    @discardableResult
    public func saveAPIKey(_ apiKey: String, for providerID: LLMProviderID) -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteAPIKey(for: providerID)
            return true
        }

        let saved = storage.save(
            account: keychainAccount(for: providerID),
            data: Data(trimmed.utf8),
            service: serviceName
        )
        guard saved else {
            return false
        }

        lock.withLock {
            loadedProviderIDs.insert(providerID)
            knownProviderStatus[providerID] = true
            cachedKeys[providerID] = trimmed
        }
        postDidChange(providerID)
        return true
    }

    @discardableResult
    public func deleteAPIKey(for providerID: LLMProviderID) -> Bool {
        let deleted = storage.delete(account: keychainAccount(for: providerID), service: serviceName)
        guard deleted else {
            return false
        }

        lock.withLock {
            loadedProviderIDs.insert(providerID)
            knownProviderStatus[providerID] = false
            cachedKeys.removeValue(forKey: providerID)
        }
        postDidChange(providerID)
        return true
    }

    private func keychainAccount(for providerID: LLMProviderID) -> String {
        "llm-api-key-\(providerID.rawValue)"
    }

    private func postDidChange(_ providerID: LLMProviderID) {
        notificationCenter.post(
            name: .llmAPIKeyStoreDidChange,
            object: self,
            userInfo: ["providerID": providerID.rawValue]
        )
    }
}
