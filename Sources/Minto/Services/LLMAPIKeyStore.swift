import Foundation
import Security

extension Notification.Name {
    public static let llmAPIKeyStoreDidChange = Notification.Name("minto.llmAPIKeyStoreDidChange")
}

protocol LLMAPIKeyStorageBackend: Sendable {
    func load(account: String, service: String) -> Data?
    func save(account: String, data: Data, service: String) -> Bool
    func delete(account: String, service: String) -> Bool
}

struct KeychainLLMAPIKeyStorageBackend: LLMAPIKeyStorageBackend {
    func load(account: String, service: String) -> Data? {
        KeychainService.load(provider: account, service: service)
    }

    func save(account: String, data: Data, service: String) -> Bool {
        KeychainService.save(provider: account, data: data, service: service) == errSecSuccess
    }

    func delete(account: String, service: String) -> Bool {
        let status = KeychainService.delete(provider: account, service: service)
        return status == errSecSuccess || status == errSecItemNotFound
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
    private var cachedKeys: [LLMProviderID: String] = [:]

    public init(serviceName: String = KeychainService.llmAPIService) {
        self.serviceName = serviceName
        self.storage = KeychainLLMAPIKeyStorageBackend()
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
            if let key {
                cachedKeys[providerID] = key
            } else {
                cachedKeys.removeValue(forKey: providerID)
            }
        }
        return key
    }

    public func hasAPIKey(for providerID: LLMProviderID) -> Bool {
        apiKey(for: providerID) != nil
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
