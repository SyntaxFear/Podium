import Foundation

/// Persists AdsCredentials as JSON in a SecretStore (Keychain in production).
public struct CredentialsStore: Sendable {
    static let key = "adsCredentials"
    let store: SecretStore

    public init(store: SecretStore) { self.store = store }

    public func load() throws -> AdsCredentials? {
        guard let data = try store.get(Self.key) else { return nil }
        return try JSONDecoder().decode(AdsCredentials.self, from: data)
    }

    public func save(_ credentials: AdsCredentials) throws {
        try store.set(JSONEncoder().encode(credentials), for: Self.key)
    }

    public func clear() throws {
        try store.delete(Self.key)
    }
}
