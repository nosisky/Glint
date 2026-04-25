import Foundation

/// Coordinates global search across a table's columns.
/// Introspects the schema to build an ILIKE query across all text-searchable
/// and cast-to-text numeric columns. Debounces rapid input.
actor SearchCoordinator {
    private let connection: PostgresConnection
    private let queryBuilder = QueryBuilder()

    init(connection: PostgresConnection) {
        self.connection = connection
    }

    /// Build a search query for the given text across all searchable columns of a table.
    /// Returns the generated SQL WHERE clause fragment (without the WHERE keyword).
    func buildSearchClause(searchText: String, table: TableInfo) -> String? {
        guard !searchText.isEmpty else { return nil }

        let escapedSearch = escapeLike(searchText)
        let pattern = "'%\(escapedSearch.replacingOccurrences(of: "'", with: "''"))%'"

        var clauses: [String] = []

        for column in table.columns {
            if column.isTextSearchable {
                clauses.append("\"\(column.name)\" ILIKE \(pattern)")
            } else if column.isNumeric {
                // Cast numeric to text for partial matching
                clauses.append("\"\(column.name)\"::text ILIKE \(pattern)")
            } else if column.isTemporal {
                // Cast temporal to text for date searching
                clauses.append("\"\(column.name)\"::text ILIKE \(pattern)")
            }
        }

        guard !clauses.isEmpty else { return nil }
        return clauses.joined(separator: " OR ")
    }

    /// Execute a search and return the result count (for preview/badge).
    func previewSearchCount(searchText: String, table: TableInfo) async throws -> Int64 {
        guard let clause = buildSearchClause(searchText: searchText, table: table) else {
            return 0
        }

        let sql = "SELECT count(*) FROM \(table.qualifiedName) WHERE \(clause)"
        return try await connection.queryScalar(sql)
    }

    /// Get matching columns for a search term (for highlighting which columns matched).
    func matchingColumns(searchText: String, table: TableInfo) -> [ColumnInfo] {
        guard !searchText.isEmpty else { return [] }
        return table.columns.filter { $0.isTextSearchable || $0.isNumeric }
    }

    // MARK: - Private

    private func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
