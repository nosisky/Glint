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

    var hasMore: Bool {
        currentOffset + pageSize < totalCount
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
