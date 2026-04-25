import Foundation

/// A generic representation of a database row.
/// Uses ordered key-value pairs to preserve column order.
struct TableRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let values: [CellValue]

    init(id: UUID = UUID(), values: [CellValue]) {
        self.id = id
        self.values = values
    }

    /// Get cell value by column index.
    subscript(index: Int) -> CellValue? {
        guard index >= 0 && index < values.count else { return nil }
        return values[index]
    }
}

/// A single cell value with its column context.
struct CellValue: Hashable, Sendable {
    let columnName: String
    let rawValue: String?       // nil = SQL NULL
    let displayValue: String    // formatted for display
    let dataType: String        // udtName

    var isNull: Bool { rawValue == nil }

    init(columnName: String, rawValue: String?, dataType: String) {
        self.columnName = columnName
        self.rawValue = rawValue
        self.dataType = dataType
        self.displayValue = rawValue ?? "NULL"
    }
}

/// Pending cell edit — tracks uncommitted changes.
struct PendingEdit: Identifiable, Hashable, Sendable {
    let id: UUID
    let rowId: UUID
    let columnIndex: Int
    let columnName: String
    let originalValue: String?
    let newValue: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        rowId: UUID,
        columnIndex: Int,
        columnName: String,
        originalValue: String?,
        newValue: String?,
        timestamp: Date = .now
    ) {
        self.id = id
        self.rowId = rowId
        self.columnIndex = columnIndex
        self.columnName = columnName
        self.originalValue = originalValue
        self.newValue = newValue
        self.timestamp = timestamp
    }

    var hasChanged: Bool {
        originalValue != newValue
    }
}
