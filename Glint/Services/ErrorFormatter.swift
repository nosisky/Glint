//
//  ErrorFormatter.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation
import PostgresNIO

/// Extracts human-readable error messages from PostgresNIO errors.
///
/// `PSQLError` intentionally hides its details behind a generic description
/// to prevent accidental leakage of sensitive data in production. This is
/// fine for server apps, but in a developer-facing database client, we need
/// the actual Postgres error message, SQL state code, detail, and hint.
enum ErrorFormatter {

    /// Extracts a human-readable description from any error,
    /// with special handling for `PSQLError`.
    static func message(from error: any Error) -> String {
        if let psqlError = error as? PSQLError {
            return formatPSQLError(psqlError)
        }

        // For LocalizedError types (e.g. ConnectionError), use errorDescription
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        // Fallback: String(describing:) is more useful than localizedDescription
        // for non-LocalizedError types
        return String(describing: error)
    }

    /// Formats a PSQLError into a readable string using the subscript-based
    /// ServerInfo API from PostgresNIO.
    private static func formatPSQLError(_ error: PSQLError) -> String {
        // Server-side errors carry the real Postgres error message
        if let serverInfo = error.serverInfo {
            var parts: [String] = []

            // Primary error message (e.g. "relation \"foo\" does not exist")
            if let msg = serverInfo[.message] {
                parts.append(msg)
            }

            // SQL state code (e.g. "42P01" for undefined_table)
            if let sqlState = serverInfo[.sqlState] {
                if !parts.isEmpty {
                    parts[0] += " [\(sqlState)]"
                } else {
                    parts.append("SQL State: \(sqlState)")
                }
            }

            // Detail provides additional context
            if let detail = serverInfo[.detail], !detail.isEmpty {
                parts.append("Detail: \(detail)")
            }

            // Hint suggests how to fix the issue
            if let hint = serverInfo[.hint], !hint.isEmpty {
                parts.append("Hint: \(hint)")
            }

            // Schema/table/column/constraint context for constraint violations
            if let schemaName = serverInfo[.schemaName] {
                parts.append("Schema: \(schemaName)")
            }
            if let tableName = serverInfo[.tableName] {
                parts.append("Table: \(tableName)")
            }
            if let columnName = serverInfo[.columnName] {
                parts.append("Column: \(columnName)")
            }
            if let constraintName = serverInfo[.constraintName] {
                parts.append("Constraint: \(constraintName)")
            }

            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }

        // Client-side errors (connection issues, decode failures, auth problems)
        // The code description gives a clean category name
        let codeDescription = error.code.description

        // Check for underlying error (e.g. connection refused, TLS failures)
        if let underlying = error.underlying {
            return "\(humanReadableCode(codeDescription)): \(underlying)"
        }

        return humanReadableCode(codeDescription)
    }

    /// Converts PSQLError.Code descriptions into user-friendly labels.
    private static func humanReadableCode(_ code: String) -> String {
        switch code {
        case "server":                      return "Server error"
        case "connectionError":             return "Connection error"
        case "serverClosedConnection":      return "Server closed the connection"
        case "clientClosedConnection":      return "Connection was closed"
        case "sslUnsupported":              return "SSL is not supported by this server"
        case "failedToAddSSLHandler":       return "Failed to establish SSL connection"
        case "authMechanismRequiresPassword": return "Password is required"
        case "unsupportedAuthMechanism":    return "Unsupported authentication method"
        case "saslError":                   return "Authentication failed"
        case "connectionTimeout":           return "Connection timed out"
        case "queryCancelled":              return "Query was cancelled"
        case "poolClosed":                  return "Connection pool is closed"
        case "uncleanShutdown":             return "Connection terminated unexpectedly"
        case "tooManyParameters":           return "Too many query parameters"
        case "messageDecodingFailure":      return "Failed to decode server response"
        default:                            return code
        }
    }
}
