import Foundation
import Security

public enum KeychainError: LocalizedError, Equatable {
    case unexpectedStatus(OSStatus)
    public var errorDescription: String? { "Keychain error (OSStatus \(rawValue))" }
    private var rawValue: Int32 {
        switch self { case .unexpectedStatus(let status): return status }
    }
}

/// Small, dependency-free wrapper around the macOS generic-password Keychain.
public struct Keychain: Sendable {
    public static let shared = Keychain()
    public let service: String

    public init(service: String = "com.skillbox.app") { self.service = service }

    public func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(account: account)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update = [kSecValueData: data] as CFDictionary
            let result = SecItemUpdate(query as CFDictionary, update)
            guard result == errSecSuccess else { throw KeychainError.unexpectedStatus(result) }
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let result = SecItemAdd(query as CFDictionary, nil)
            guard result == errSecSuccess else { throw KeychainError.unexpectedStatus(result) }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func get(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func contains(account: String) -> Bool { (try? get(account: account)) != nil }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
