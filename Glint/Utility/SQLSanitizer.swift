import Foundation

struct SQLSanitizer: Sendable {

    static func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Quote a string literal using standard SQL escaping (double single-quotes).
    /// Does NOT use PostgreSQL E-string syntax — standard_conforming_strings is ON
    /// by default since PG 9.1, making backslash interpretation unnecessary and risky.
    static func quoteLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "'", with: "''")
            .replacingOccurrences(of: "\0", with: "")
        return "'\(escaped)'"
    }

    /// Escape LIKE pattern metacharacters.
    /// Uses the default backslash escape character for LIKE patterns.
    static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - Destructive Query Detection

    /// Keywords that indicate a destructive SQL operation.
    private static let destructiveKeywords: [String] = [
        "DROP", "TRUNCATE", "DELETE", "ALTER", "UPDATE", "GRANT", "REVOKE"
    ]

    /// Returns true if the SQL statement appears to be a destructive operation
    /// (DROP, TRUNCATE, DELETE, ALTER, UPDATE, GRANT, REVOKE).
    static func isDestructive(_ sql: String) -> Bool {
        let upper = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return destructiveKeywords.contains { upper.hasPrefix($0) }
    }

    /// Returns true if a DELETE/UPDATE statement lacks a WHERE clause,
    /// which would affect all rows in the table.
    static func lacksWhereClause(_ sql: String) -> Bool {
        let upper = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isTargeted = upper.hasPrefix("DELETE") || upper.hasPrefix("UPDATE")
        guard isTargeted else { return false }
        return !upper.contains("WHERE")
    }

    /// Describes the risk level of a query for display in confirmation dialogs.
    static func destructiveDescription(_ sql: String) -> String? {
        let upper = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper.hasPrefix("DROP") { return "This will permanently drop a database object." }
        if upper.hasPrefix("TRUNCATE") { return "This will permanently delete ALL rows from the table." }
        if upper.hasPrefix("DELETE") {
            if lacksWhereClause(sql) {
                return "⚠️ DELETE without WHERE — this will delete ALL rows in the table."
            }
            return "This will delete rows from the table."
        }
        if upper.hasPrefix("UPDATE") {
            if lacksWhereClause(sql) {
                return "⚠️ UPDATE without WHERE — this will modify ALL rows in the table."
            }
            return "This will modify rows in the table."
        }
        if upper.hasPrefix("ALTER") { return "This will alter a database object's structure." }
        return nil
    }
}
