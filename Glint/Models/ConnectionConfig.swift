import Foundation

/// Represents a saved PostgreSQL connection configuration.
/// Passwords are stored in the macOS Keychain, referenced by `id`.
struct ConnectionConfig: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var database: String
    var user: String
    var useSSL: Bool
    var sshTunnel: SSHTunnelConfig?
    var colorTag: ColorTag

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
        useSSL: Bool = false,
        sshTunnel: SSHTunnelConfig? = nil,
        colorTag: ColorTag = .none
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.useSSL = useSSL
        self.sshTunnel = sshTunnel
        self.colorTag = colorTag
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
