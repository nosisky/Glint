//
//  FilterConstraint.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation

struct FilterConstraint: Identifiable, Hashable, Sendable {
    let id: UUID
    let columnName: String
    let columnType: String
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

    var displayValue: String { value.displayString }
}

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

    var displayLabel: String { rawValue }
    var symbol: String { rawValue }
}

enum FilterValue: Hashable, Sendable {
    case text(String)
    case number(Double)
    case range(low: Double, high: Double)
    case date(Date)
    case dateRange(from: Date, to: Date)
    case boolean(Bool)
    case list([String])
    case none

    var displayString: String {
        switch self {
        case .text(let s): s
        case .number(let n): String(n)
        case .range(let lo, let hi): "\(lo) – \(hi)"
        case .date(let d): d.formatted(.dateTime.year().month().day())
        case .dateRange(let from, let to):
            "\(from.formatted(.dateTime.month().day())) – \(to.formatted(.dateTime.month().day()))"
        case .boolean(let b): b ? "true" : "false"
        case .list(let items): items.joined(separator: ", ")
        case .none: "—"
        }
    }
}
