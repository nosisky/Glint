import Foundation

// MARK: - String Extensions

extension String {
    /// Truncate to a maximum length with ellipsis.
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength - 1)) + "…"
    }
}

// MARK: - Int64 Extensions

extension Int64 {
    /// Format as a human-readable count (e.g., 1.2M, 450K).
    var formattedCount: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        }
        if self >= 1_000 {
            return String(format: "%.1fK", Double(self) / 1_000)
        }
        return "\(self)"
    }
}
