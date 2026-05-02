//
//  QueryHistory.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation

/// A single entry in the per-tab query execution history.
struct QueryHistoryEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let sql: String
    let executedAt: Date
    let durationMs: Double
    let rowCount: Int64
    let wasError: Bool
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        sql: String,
        executedAt: Date = Date(),
        durationMs: Double = 0,
        rowCount: Int64 = 0,
        wasError: Bool = false,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sql = sql
        self.executedAt = executedAt
        self.durationMs = durationMs
        self.rowCount = rowCount
        self.wasError = wasError
        self.errorMessage = errorMessage
    }
}
