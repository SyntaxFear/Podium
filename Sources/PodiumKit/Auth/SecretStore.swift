import Foundation
import Security

public protocol SecretStore: Sendable {
    func set(_ data: Data, for key: String) throws
    func get(_ key: String) throws -> Data?
    func delete(_ key: String) throws
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func set(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }
    public func get(_ key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
    public func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}

/// Thin macOS Keychain adapter (kSecClassGenericPassword under the "app.podium" service).
/// Not unit-tested — exercised via the smoke CLI and the app.
public struct KeychainSecretStore: SecretStore {
    public let service: String
    public init(service: String = "app.podium") { self.service = service }

    public func set(_ data: Data, for key: String) throws {
        try delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PodiumError.keychain(status) }
    }

    public func get(_ key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PodiumError.keychain(status) }
        return result as? Data
    }

    public func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PodiumError.keychain(status)
        }
    }
}

public enum PodiumError: Error, Equatable {
    case keychain(OSStatus)
    case missingCredentials
    case http(status: Int, body: String)
    case rateLimited
    case decoding(String)
}
