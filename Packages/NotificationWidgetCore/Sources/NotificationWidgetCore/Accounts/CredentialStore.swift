import Foundation
import Security

/// Where secrets such as the Slack tokens are kept (APP-3).
public protocol CredentialStore: Sendable {
    func load(_ key: String) -> Data?
    func save(_ data: Data, for key: String) throws
    func delete(_ key: String)
}

public extension CredentialStore {
    func loadValue<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        load(key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func saveValue<T: Encodable>(_ value: T, for key: String) throws {
        try save(JSONEncoder().encode(value), for: key)
    }
}

/// Stores secrets as generic passwords in the macOS Keychain.
public struct KeychainCredentialStore: CredentialStore {
    public struct KeychainError: Error, Equatable { public var status: OSStatus }

    private let service: String

    public init(service: String = "com.adrianeyre.NotificationWidget") {
        self.service = service
    }

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    public func load(_ key: String) -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    public func save(_ data: Data, for key: String) throws {
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}

/// Keeps secrets in memory. For tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func load(_ key: String) -> Data? { lock.withLock { values[key] } }
    public func save(_ data: Data, for key: String) throws { lock.withLock { values[key] = data } }
    public func delete(_ key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
}
