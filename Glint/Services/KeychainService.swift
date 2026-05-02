//
//  KeychainService.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation

/// A secure storage service that uses obfuscated UserDefaults to avoid the constant
/// macOS Keychain security prompts that occur when running unsigned binaries via `swift run`.
struct KeychainService: Sendable {
    private static let keyPrefix = "glint.secure."
    private static let obfuscationKey: [UInt8] = [0x47, 0x6C, 0x69, 0x6E, 0x74, 0x53, 0x65, 0x63, 0x75, 0x72, 0x65] // "GlintSecure"

    enum KeychainError: LocalizedError, Sendable {
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData

        var errorDescription: String? {
            switch self {
            case .saveFailed: "Storage save failed"
            case .readFailed: "Storage read failed"
            case .deleteFailed: "Storage delete failed"
            case .unexpectedData: "Unexpected storage data format."
            }
        }
    }

    private static func obfuscate(_ data: Data) -> Data {
        var result = Data(capacity: data.count)
        for (i, byte) in data.enumerated() {
            let keyByte = obfuscationKey[i % obfuscationKey.count]
            result.append(byte ^ keyByte)
        }
        return result
    }

    static func savePassword(_ password: String, account: String) throws {
        let data = Data(password.utf8)
        let obfuscated = obfuscate(data)
        UserDefaults.standard.set(obfuscated.base64EncodedString(), forKey: keyPrefix + account)
    }

    static func readPassword(account: String) throws -> String? {
        guard let base64 = UserDefaults.standard.string(forKey: keyPrefix + account),
              let obfuscated = Data(base64Encoded: base64) else {
            return nil
        }
        
        let data = obfuscate(obfuscated)
        guard let pw = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return pw
    }

    static func deletePassword(account: String) throws {
        UserDefaults.standard.removeObject(forKey: keyPrefix + account)
    }
}
