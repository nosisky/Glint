//
//  ConnectionConfig.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation

enum SSLMode: String, Codable, Hashable, Sendable, CaseIterable {
    case disable
    case prefer
    case require
    case verifyCA = "verify-ca"
    case verifyFull = "verify-full"
    
    var displayName: String {
        switch self {
            case .disable: return "Disable"
        case .prefer: return "Prefer"
        case .require: return "Require"
        case .verifyCA: return "Verify-CA"
        case .verifyFull: return "Verify-Full"
        }
    }
}

/// Represents a saved PostgreSQL connection configuration.
/// Passwords are stored in the macOS Keychain, referenced by `id`.
struct ConnectionConfig: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var database: String
    var user: String
    var sslMode: SSLMode
    var sshTunnel: SSHTunnelConfig?
    var colorTag: ColorTag

    // mTLS & Advanced Options
    var serverCACertPath: String?
    var clientCertPath: String?
    var clientKeyPath: String?
    var startupQuery: String?
    var preConnectScript: String?

    /// Deprecated field retained solely for JSON migration
    private var useSSL: Bool?

    /// Keychain account identifier for password retrieval.
    var keychainAccount: String {
        "glint-pg-\(id.uuidString)"
    }

    init(
        id: UUID = UUID(),
        name: String = "New Connection",
        host: String = "localhost",
        port: Int = 5432,
        database: String = "postgres",
        user: String = "postgres",
        sslMode: SSLMode = .disable,
        sshTunnel: SSHTunnelConfig? = nil,
        colorTag: ColorTag = .blue,
        serverCACertPath: String? = nil,
        clientCertPath: String? = nil,
        clientKeyPath: String? = nil,
        startupQuery: String? = nil,
        preConnectScript: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.sslMode = sslMode
        self.sshTunnel = sshTunnel
        self.colorTag = colorTag
        self.serverCACertPath = serverCACertPath
        self.clientCertPath = clientCertPath
        self.clientKeyPath = clientKeyPath
        self.startupQuery = startupQuery
        self.preConnectScript = preConnectScript
    }

    // MARK: - Codable Migration
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, database, user, sslMode, useSSL, sshTunnel, colorTag
        case serverCACertPath, clientCertPath, clientKeyPath, startupQuery, preConnectScript
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Connection"
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? "localhost"
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 5432
        self.database = try container.decodeIfPresent(String.self, forKey: .database) ?? "postgres"
        self.user = try container.decodeIfPresent(String.self, forKey: .user) ?? "postgres"
        
        // Migrate legacy useSSL to sslMode
        if let mode = try container.decodeIfPresent(SSLMode.self, forKey: .sslMode) {
            self.sslMode = mode
        } else if let legacySSL = try container.decodeIfPresent(Bool.self, forKey: .useSSL) {
            self.sslMode = legacySSL ? .prefer : .disable
        } else {
            self.sslMode = .disable
        }

        self.sshTunnel = try container.decodeIfPresent(SSHTunnelConfig.self, forKey: .sshTunnel)
        self.colorTag = try container.decodeIfPresent(ColorTag.self, forKey: .colorTag) ?? .blue
        self.serverCACertPath = try container.decodeIfPresent(String.self, forKey: .serverCACertPath)
        self.clientCertPath = try container.decodeIfPresent(String.self, forKey: .clientCertPath)
        self.clientKeyPath = try container.decodeIfPresent(String.self, forKey: .clientKeyPath)
        self.startupQuery = try container.decodeIfPresent(String.self, forKey: .startupQuery)
        self.preConnectScript = try container.decodeIfPresent(String.self, forKey: .preConnectScript)
    }
}

// MARK: - SSH Tunnel Configuration

struct SSHTunnelConfig: Codable, Hashable, Sendable {
    var sshHost: String
    var sshPort: Int
    var sshUser: String
    var localPort: Int
    var authMethod: SSHAuthMethod

    init(
        sshHost: String = "",
        sshPort: Int = 22,
        sshUser: String = "",
        localPort: Int = 5433,
        authMethod: SSHAuthMethod = .password
    ) {
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.localPort = localPort
        self.authMethod = authMethod
    }
}

enum SSHAuthMethod: String, Codable, Hashable, Sendable, CaseIterable {
    case password
    case keyFile
    case agent
}

// MARK: - Color Tag

enum ColorTag: String, Codable, Hashable, Sendable, CaseIterable {
    case none
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    var displayName: String {
        switch self {
        case .none: "None"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        }
    }
}

// MARK: - URI Parsing
extension ConnectionConfig {
    /// Attempts to parse a postgresql:// URI and apply its properties.
    /// Returns the extracted password if present in the URI.
    mutating func apply(fromURI uriString: String) -> String? {
        let trimmed = uriString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), 
              url.scheme == "postgresql" || url.scheme == "postgres" else {
            return nil
        }
        
        if let host = url.host { self.host = host }
        if let port = url.port { self.port = port }
        if let user = url.user { self.user = user }
        
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty { self.database = path }
        
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name.lowercased() == "sslmode", let val = item.value?.lowercased() {
                    self.sslMode = SSLMode(rawValue: val) ?? self.sslMode
                }
            }
        }
        
        // Use a clean display name if it's currently default
        if self.name == "New Connection" || self.name.isEmpty {
            self.name = "\(self.user)@\(self.host)"
        }
        
        return url.password
    }
}
