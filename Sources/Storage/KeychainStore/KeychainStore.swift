import Foundation
import Security

public enum KeychainStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(Int32)
}

public struct KeychainStore: Sendable {
    public static let defaultService = "CodexQuotaManager"

    public var defaultService: String

    public init(defaultService: String = Self.defaultService) {
        self.defaultService = defaultService
    }

    public func accountReference(accountID: UUID) -> String {
        "codex-quota-manager.account.\(accountID.uuidString)"
    }

    public func saveSecret(_ secret: Data, reference: String) throws {
        try saveSecret(secret, service: defaultService, account: reference)
    }

    public func readSecret(reference: String) throws -> Data? {
        try readSecret(service: defaultService, account: reference)
    }

    @discardableResult
    public func deleteSecret(reference: String) throws -> Bool {
        try deleteSecret(service: defaultService, account: reference)
    }

    public func saveSecret(_ secret: Data, service: String, account: String) throws {
        _ = try deleteSecret(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: secret
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    public func readSecret(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        return item as? Data
    }

    @discardableResult
    public func deleteSecret(service: String, account: String) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound {
            return false
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        return true
    }
}
