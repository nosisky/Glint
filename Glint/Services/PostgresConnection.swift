import Foundation
import PostgresNIO
import Logging
import NIOCore

/// Actor wrapping PostgresClient — manages the connection lifecycle.
/// PostgresClient already has a built-in connection pool, so we just wrap it
/// with actor isolation for safe access from SwiftUI.
actor PostgresConnection {
    private var client: PostgresClient?
    private var clientTask: Task<Void, Never>?
    private let config: ConnectionConfig
    private let password: String
    private let logger: Logger

    enum ConnectionError: LocalizedError, Sendable {
        case notConnected
        case connectionFailed(String)
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Not connected to database."
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            case .queryFailed(let reason):
                return "Query failed: \(reason)"
            }
        }
    }

    init(config: ConnectionConfig, password: String) {
        self.config = config
        self.password = password
        self.logger = Logger(label: "glint.postgres.\(config.name)")
    }

    // MARK: - Lifecycle

    func connect() async throws {
        // Cancel any existing connection first
        disconnect()

        var tlsConfig: PostgresClient.Configuration.TLS = .disable
        let isLocalhost = config.host == "localhost" || config.host == "127.0.0.1"
        if config.useSSL || !isLocalhost {
            tlsConfig = .prefer(.makeClientConfiguration())
        }

        let pgConfig = PostgresClient.Configuration(
            host: config.host,
            port: config.port,
            username: config.user,
            password: password,
            database: config.database,
            tls: tlsConfig
        )

        let newClient = PostgresClient(configuration: pgConfig, backgroundLogger: logger)

        // Run the client's event loop in a background task.
        let task = Task {
            await newClient.run()
        }
        clientTask = task
        self.client = newClient

        // Verify connectivity — if this fails, tear down immediately
        // to prevent the pool from retrying with bad credentials.
        do {
            _ = try await newClient.query("SELECT 1")
            logger.info("Connected to \(config.host):\(config.port)/\(config.database)")
        } catch {
            // Tear down the client to stop retry loop
            task.cancel()
            clientTask = nil
            client = nil
            throw ConnectionError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() {
        clientTask?.cancel()
        clientTask = nil
        client = nil
        logger.info("Disconnected from \(config.host)")
    }

    var isConnected: Bool {
        client != nil
    }

    // MARK: - Query Execution

    /// Execute a query and return the row sequence.
    func query(_ sql: String) async throws -> PostgresRowSequence {
        guard let client else { throw ConnectionError.notConnected }
        let pgQuery = PostgresQuery(unsafeSQL: sql)
        return try await client.query(pgQuery)
    }

    /// Execute a query and collect all rows.
    func queryAll(_ sql: String) async throws -> [PostgresRow] {
        let rows = try await query(sql)
        var collected: [PostgresRow] = []
        for try await row in rows {
            collected.append(row)
        }
        return collected
    }

    /// Execute a single-value scalar query (e.g., SELECT count(*)).
    func queryScalar(_ sql: String) async throws -> Int64 {
        let rows = try await query(sql)
        for try await row in rows {
            let randomAccess = row.makeRandomAccess()
            return try randomAccess[0].decode(Int64.self)
        }
        throw ConnectionError.queryFailed("No rows returned for scalar query")
    }

    /// Get the underlying client for withConnection patterns.
    func getClient() throws -> PostgresClient {
        guard let client else { throw ConnectionError.notConnected }
        return client
    }

    var connectionInfo: String {
        "\(config.user)@\(config.host):\(config.port)/\(config.database)"
    }
}
