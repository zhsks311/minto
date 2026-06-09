import Foundation
import Security

protocol SecretStore: Sendable {
    func exists(account: String, service: String) -> Bool
    func load(account: String, service: String) -> Data?
    func save(account: String, data: Data, service: String) -> Bool
    func delete(account: String, service: String) -> Bool
}

struct KeychainSecretStore: SecretStore {
    func exists(account: String, service: String) -> Bool {
        KeychainService.exists(provider: account, service: service)
    }

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

final class LocalDevSecretStore: SecretStore, @unchecked Sendable {
    private struct StoredSecret: Codable {
        let schemaVersion: Int
        let service: String
        let account: String
        let dataBase64: String
    }

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(
        rootDirectory: URL = LocalDevSecretStore.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func exists(account: String, service: String) -> Bool {
        lock.withLock {
            fileManager.fileExists(atPath: fileURL(account: account, service: service).path)
        }
    }

    func load(account: String, service: String) -> Data? {
        lock.withLock {
            let url = fileURL(account: account, service: service)
            guard let data = try? Data(contentsOf: url),
                  let stored = try? JSONDecoder().decode(StoredSecret.self, from: data),
                  stored.service == service,
                  stored.account == account,
                  let secret = Data(base64Encoded: stored.dataBase64)
            else {
                return nil
            }
            return secret
        }
    }

    func save(account: String, data: Data, service: String) -> Bool {
        lock.withLock {
            do {
                try ensureRootDirectory()
                let stored = StoredSecret(
                    schemaVersion: 1,
                    service: service,
                    account: account,
                    dataBase64: data.base64EncodedString()
                )
                let encoded = try JSONEncoder().encode(stored)
                let url = fileURL(account: account, service: service)
                try encoded.write(to: url, options: [.atomic])
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                return true
            } catch {
                return false
            }
        }
    }

    func delete(account: String, service: String) -> Bool {
        lock.withLock {
            let url = fileURL(account: account, service: service)
            guard fileManager.fileExists(atPath: url.path) else { return true }
            do {
                try fileManager.removeItem(at: url)
                return true
            } catch {
                return false
            }
        }
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path)
    }

    private func fileURL(account: String, service: String) -> URL {
        let fileName = safeComponent(service) + "__" + safeComponent(account) + ".json"
        return rootDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let safe = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return safe.isEmpty ? "secret" : safe
    }

    fileprivate static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Minto", isDirectory: true)
            .appendingPathComponent("dev-secrets", isDirectory: true)
    }
}

enum SecretStoreFactory {
    static let devStoreModeEnvironmentKey = "MINTO_DEV_SECRET_STORE"
    static let devStoreRootEnvironmentKey = "MINTO_DEV_SECRET_STORE_ROOT"

    static func make(environment: [String: String] = ProcessInfo.processInfo.environment) -> any SecretStore {
        switch environment[devStoreModeEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "file", "local-file", "local":
            return LocalDevSecretStore(rootDirectory: devStoreRootDirectory(environment: environment))
        default:
            return KeychainSecretStore()
        }
    }

    private static func devStoreRootDirectory(environment: [String: String]) -> URL {
        guard let rawPath = environment[devStoreRootEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty
        else {
            return LocalDevSecretStore.defaultRootDirectory()
        }
        return URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath, isDirectory: true)
    }
}
