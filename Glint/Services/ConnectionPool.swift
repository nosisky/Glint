import Foundation

/// Actor managing the active PostgreSQL connection.
/// Wraps a single PostgresConnection actor (which itself uses PostgresClient's
/// built-in connection pool under the hood).
actor ConnectionPool {
    private var connection: PostgresConnection?
    nonisolated let config: ConnectionConfig
    private let password: String

    enum PoolError: LocalizedError, Sendable {
        case noActiveConnection

        var errorDescription: String? {
            switch self {
            case .noActiveConnection:
                return "No active database connection."
            }
        }
    }

    init(config: ConnectionConfig, password: String) {
        self.config = config
        self.password = password
    }

    func connect() async throws {
        let conn = PostgresConnection(config: config, password: password)
        try await conn.connect()
        connection = conn
    }

    func disconnectAll() async {
        if let connection {
            await connection.disconnectAndAwait()
        }
        connection = nil
    }

    func getConnection() throws -> PostgresConnection {
        guard let connection else {
            throw PoolError.noActiveConnection
        }
        return connection
    }

    var isConnected: Bool {
        get async {
            guard let connection else { return false }
            return await connection.isConnected
        }
    }
}
