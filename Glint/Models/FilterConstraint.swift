import Foundation

/// A single filter condition applied to a column.
/// The QueryBuilder compiles an array of these into a WHERE clause.
struct FilterConstraint: Identifiable, Hashable, Sendable {
    let id: UUID
    let columnName: String
    let columnType: String  // udtName for type-aware SQL generation
    let operation: FilterOperation
    let value: FilterValue

    init(
        id: UUID = UUID(),
        columnName: String,
        columnType: String,
        operation: FilterOperation,
        value: FilterValue
    ) {
        self.id = id
        self.columnName = columnName
        self.columnType = columnType
        self.operation = operation
        self.value = value
    }
}

/// Supported filter operations.
enum FilterOperation: String, Hashable, Sendable, CaseIterable {
    case equals = "="
    case notEquals = "≠"
    case contains = "Contains"
    case startsWith = "Starts with"
    case endsWith = "Ends with"
    case greaterThan = ">"
    case lessThan = "<"
    case greaterOrEqual = "≥"
    case lessOrEqual = "≤"
    case between = "Between"
    case isNull = "Is NULL"
    case isNotNull = "Is NOT NULL"
    case inList = "In List"

    var requiresValue: Bool {
        switch self {
        case .isNull, .isNotNull: false
        default: true
        }
    }

    /// Human-readable label for the popover UI.
    var displayLabel: String { rawValue }
}

/// Type-safe filter value container.
enum FilterValue: Hashable, Sendable {
    case text(String)
    case number(Double)
    case range(low: Double, high: Double)
    case date(Date)
    case dateRange(from: Date, to: Date)
    case boolean(Bool)
    case list([String])
    case none // for isNull / isNotNull

    var displayString: String {
        switch self {
        case .text(let s): return s
        case .number(let n): return String(n)
        case .range(let lo, let hi): return "\(lo) – \(hi)"
        case .date(let d): return d.formatted(.dateTime.year().month().day())
        case .dateRange(let from, let to):
            return "\(from.formatted(.dateTime.month().day())) – \(to.formatted(.dateTime.month().day()))"
        case .boolean(let b): return b ? "true" : "false"
        case .list(let items): return items.joined(separator: ", ")
        case .none: return "—"
        }
    }
}
