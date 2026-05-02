//
//  QueryResult.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation

/// Paginated query result envelope.
struct QueryResult: Sendable {
    let rows: [TableRow]
    let columns: [ColumnInfo]
    let totalCount: Int64       // total matching rows (for pagination UI)
    let pageSize: Int
    let currentOffset: Int
    let executionTimeMs: Double // query execution time for status bar
    let query: String           // raw SQL (hidden from user by default)
    let explicitHasMore: Bool?  // Used when totalCount is unknown (e.g. custom queries)

    var hasMore: Bool {
        if let explicit = explicitHasMore { return explicit }
        return currentOffset + pageSize < totalCount
    }

    init(rows: [TableRow], columns: [ColumnInfo], totalCount: Int64, pageSize: Int, currentOffset: Int, executionTimeMs: Double, query: String, hasMore: Bool? = nil) {
        self.rows = rows
        self.columns = columns
        self.totalCount = totalCount
        self.pageSize = pageSize
        self.currentOffset = currentOffset
        self.executionTimeMs = executionTimeMs
        self.query = query
        self.explicitHasMore = hasMore
    }

    var currentPage: Int {
        (currentOffset / max(pageSize, 1)) + 1
    }

    var totalPages: Int {
        Int(ceil(Double(totalCount) / Double(max(pageSize, 1))))
    }

    static let empty = QueryResult(
        rows: [],
        columns: [],
        totalCount: 0,
        pageSize: 200,
        currentOffset: 0,
        executionTimeMs: 0,
        query: ""
    )
}
