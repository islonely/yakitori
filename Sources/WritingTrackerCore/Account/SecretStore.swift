import Foundation
import Security

/// Abstraction over secret storage so tests never touch the real Keychain.
public protocol SecretStoring: AnyObject {
    func string(for key: String) throws -> String?
    func set(_ value: String, for key: String) throws
    func remove(_ key: String) throws
}

public enum SecretStoreError: LocalizedError {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain error \(status)."
        }
    }
}

/// macOS Keychain-backed store. The API token and installation id live here,
/// never in `UserDefaults`.
public final class KeychainSecretStore: SecretStoring {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.yakitori.app", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func string(for key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecretStoreError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw SecretStoreError.keychain(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.keychain(addStatus)
        }
    }

    public func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init(seed: [String: String] = [:]) {
        self.storage = seed
    }

    public func string(for key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    public func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
