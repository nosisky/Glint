import Foundation
import Security

/// Native macOS Keychain integration for secure password storage.
struct KeychainService: Sendable {
    private static let service = "com.glint.postgres"

    enum KeychainError: LocalizedError, Sendable {
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData

        var errorDescription: String? {
            switch self {
            case .saveFailed(let s): "Keychain save failed: \(s)"
            case .readFailed(let s): "Keychain read failed: \(s)"
            case .deleteFailed(let s): "Keychain delete failed: \(s)"
            case .unexpectedData: "Unexpected keychain data format."
            }
        }
    }

    static func savePassword(_ password: String, account: String) throws {
        let data = Data(password.utf8)
        let search: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(search as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var add = search
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    static func readPassword(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.readFailed(status) }
        guard let data = result as? Data, let pw = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return pw
    }

    static func deletePassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
