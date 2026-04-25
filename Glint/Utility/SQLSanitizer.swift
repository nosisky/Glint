import Foundation

/// SQL string sanitization utilities.
struct SQLSanitizer: Sendable {
    
    /// Sanitize an identifier (table/column name) for safe use in SQL.
    static func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Sanitize a string literal for safe use in SQL.
    static func quoteLiteral(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }

    /// Check if a string contains potential SQL injection patterns.
    static func isSuspicious(_ input: String) -> Bool {
        let patterns = ["--", ";", "/*", "*/", "xp_", "exec(", "execute("]
        return patterns.contains { input.lowercased().contains($0) }
    }
}
