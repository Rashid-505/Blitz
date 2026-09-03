import Foundation
import Security

enum KeychainStore {
    private static let service = "com.rashidhuseynov.Blitz"

    static func store(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        let baseQuery: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        key,
            kSecAttrService:        service,
            kSecAttrSynchronizable: kCFBooleanFalse!
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData]   = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.storeFailed(status) }
    }

    static func retrieve(forKey key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        key,
            kSecAttrService:        service,
            kSecAttrSynchronizable: kCFBooleanFalse!,
            kSecReturnData:         true,
            kSecMatchLimit:         kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.retrieveFailed(status) }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        key,
            kSecAttrService:        service,
            kSecAttrSynchronizable: kCFBooleanFalse!
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: Error, LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .storeFailed(let s):    return "Keychain write failed (OSStatus \(s))"
        case .retrieveFailed(let s): return "Keychain read failed (OSStatus \(s))"
        case .deleteFailed(let s):   return "Keychain delete failed (OSStatus \(s))"
        }
    }
}
