//
//  KeychainService.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation
import Security

/// A secure storage service that uses the native macOS Keychain.
struct KeychainService: Sendable {
    private static let serviceName = "com.nosisky.glint"
    private static let legacyKeyPrefix = "glint.secure."
    private static let legacyObfuscationKey: [UInt8] = [0x47, 0x6C, 0x69, 0x6E, 0x74, 0x53, 0x65, 0x63, 0x75, 0x72, 0x65] // "GlintSecure"

    enum KeychainError: LocalizedError, Sendable {
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status): return "Keychain save failed with status: \(status)"
            case .readFailed(let status): return "Keychain read failed with status: \(status)"
            case .deleteFailed(let status): return "Keychain delete failed with status: \(status)"
            case .unexpectedData: return "Unexpected storage data format."
            }
        }
    }

    // MARK: - Legacy Migration Logic
    
    private static func legacyObfuscate(_ data: Data) -> Data {
        var result = Data(capacity: data.count)
        for (i, byte) in data.enumerated() {
            let keyByte = legacyObfuscationKey[i % legacyObfuscationKey.count]
            result.append(byte ^ keyByte)
        }
        return result
    }

    /// Migrates a legacy XOR-obfuscated password to the secure native Keychain.
    private static func migrateLegacyPasswordIfNeeded(account: String) {
        guard let base64 = UserDefaults.standard.string(forKey: legacyKeyPrefix + account),
              let obfuscated = Data(base64Encoded: base64) else {
            return
        }
        
        let data = legacyObfuscate(obfuscated)
        if let pw = String(data: data, encoding: .utf8) {
            // Save to new secure keychain
            try? savePassword(pw, account: account)
            // Erase legacy insecure entry
            UserDefaults.standard.removeObject(forKey: legacyKeyPrefix + account)
            print("[Glint] Successfully migrated legacy connection credentials for \(account).")
        }
    }

    // MARK: - Native Keychain API

    static func savePassword(_ password: String, account: String) throws {
        let passwordData = Data(password.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            // Item exists, update it
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: passwordData
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            if updateStatus != errSecSuccess {
                throw KeychainError.saveFailed(updateStatus)
            }
        } else if status == errSecItemNotFound {
            // Item does not exist, add it
            var newItem = query
            newItem[kSecValueData as String] = passwordData
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.saveFailed(addStatus)
            }
        } else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func readPassword(account: String) throws -> String? {
        // Attempt migration just-in-time
        migrateLegacyPasswordIfNeeded(account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            guard let data = dataTypeRef as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return password
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw KeychainError.readFailed(status)
        }
    }

    static func deletePassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
        
        // Also cleanup legacy entry if it was lingering
        UserDefaults.standard.removeObject(forKey: legacyKeyPrefix + account)
    }
}
