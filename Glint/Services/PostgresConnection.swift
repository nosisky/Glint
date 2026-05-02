//
//  PostgresConnection.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

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
    private var isConnectingInProgress = false

    /// Connection timeout in seconds.
    static let connectionTimeoutSeconds: UInt64 = 10

    enum ConnectionError: LocalizedError, Sendable {
        case notConnected
        case connectionFailed(String)
        case queryFailed(String)
        case connectionTimeout

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Not connected to database."
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            case .queryFailed(let reason):
                return "Query failed: \(reason)"
            case .connectionTimeout:
                return "Connection timed out after \(PostgresConnection.connectionTimeoutSeconds) seconds."
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
        // Prevent re-entrant connects from causing task leaks
        guard !isConnectingInProgress else {
            logger.warning("Connect already in progress, ignoring duplicate call")
            return
        }
        isConnectingInProgress = true
        defer { isConnectingInProgress = false }

        // Tear down any existing connection first and wait for cleanup
        await disconnectAndAwait()

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

        // Allow the run loop to start before issuing queries.
        // Without this yield, the SELECT 1 verification can race ahead
        // of PostgresClient.run() and trigger a warning/failure.
        await Task.yield()

        // Verify connectivity with a timeout — if this fails or times out,
        // tear down immediately to prevent the pool from retrying with bad credentials.
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try await newClient.query("SELECT 1")
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: Self.connectionTimeoutSeconds * 1_000_000_000)
                    throw ConnectionError.connectionTimeout
                }
                // Wait for whichever finishes first
                try await group.next()
                // Cancel the remaining task (either the timeout or the query)
                group.cancelAll()
            }

            // CONN-04: Set a default statement timeout to prevent runaway queries
            if let result = try? await newClient.query(PostgresQuery(unsafeSQL: "SET statement_timeout = '30000'")) {
                for try await _ in result {}
            }

            logger.info("Connected to \(config.host):\(config.port)/\(config.database)")
        } catch {
            // Tear down the client to stop retry loop
            task.cancel()
            clientTask = nil
            client = nil
            if error is ConnectionError {
                throw error
            }
            throw ConnectionError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() {
        clientTask?.cancel()
        clientTask = nil
        client = nil
        logger.info("Disconnected from \(config.host)")
    }

    /// Disconnect and await the client task teardown to ensure resources are freed.
    func disconnectAndAwait() async {
        guard let task = clientTask else { return }
        task.cancel()
        clientTask = nil
        client = nil
        // Give the event loop a moment to wind down
        _ = await task.result
        logger.info("Disconnected (awaited) from \(config.host)")
    }

    var isConnected: Bool {
        client != nil
    }

    /// Actively verifies the connection is alive by pinging the database.
    func healthCheck() async -> Bool {
        guard let client else { return false }
        do {
            _ = try await client.query(PostgresQuery(unsafeSQL: "SELECT 1"))
            return true
        } catch {
            logger.warning("Health check failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Query Execution

    /// Execute a query and return the row sequence.
    func query(_ sql: String) async throws -> PostgresRowSequence {
        guard let client else { throw ConnectionError.notConnected }
        let pgQuery = PostgresQuery(unsafeSQL: sql)
        return try await client.query(pgQuery)
    }

    /// Execute a statement and discard all results.
    /// Use for INSERT, UPDATE, DELETE, BEGIN, COMMIT, ROLLBACK, SET, etc.
    /// PostgresNIO requires the row sequence to be fully drained before
    /// the connection can issue another query — discarding with `_` is NOT enough.
    @discardableResult
    func execute(_ sql: String) async throws -> Int {
        let rows = try await query(sql)
        var count = 0
        for try await _ in rows { count += 1 }
        return count
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

