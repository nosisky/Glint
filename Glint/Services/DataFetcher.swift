import Foundation
import PostgresNIO

/// Service responsible for fetching paginated data from PostgreSQL.
/// Uses the QueryBuilder to compile filters and handles row materialization.
actor DataFetcher {
    private let connection: PostgresConnection
    private let queryBuilder = QueryBuilder()

    init(connection: PostgresConnection) {
        self.connection = connection
    }

    /// Fetch rows with filters, global search, and pagination.
    func fetch(
        table: TableInfo,
        filters: [FilterConstraint] = [],
        globalSearch: String? = nil,
        orderBy: String? = nil,
        ascending: Bool = true,
        pageSize: Int = 200,
        offset: Int = 0
    ) async throws -> QueryResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let (sql, countSQL) = queryBuilder.buildQuery(
            table: table,
            filters: filters,
            globalSearch: globalSearch,
            orderBy: orderBy,
            ascending: ascending,
            limit: pageSize,
            offset: offset
        )

        // Execute count query
        let totalCount = try await connection.queryScalar(countSQL)

        // Execute data query
        let rawRows = try await connection.queryAll(sql)

        // Materialize rows into our generic TableRow model
        let rows = materializeRows(rawRows, columns: table.columns)

        let executionTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        return QueryResult(
            rows: rows,
            columns: table.columns,
            totalCount: totalCount,
            pageSize: pageSize,
            currentOffset: offset,
            executionTimeMs: executionTime,
            query: sql
        )
    }

    // MARK: - Row Materialization

    /// Convert PostgresNIO rows into our generic TableRow representation.
    private func materializeRows(_ pgRows: [PostgresRow], columns: [ColumnInfo]) -> [TableRow] {
        pgRows.map { pgRow in
            let randomAccess = pgRow.makeRandomAccess()
            var values: [CellValue] = []

            for (index, column) in columns.enumerated() {
                guard index < randomAccess.count else {
                    values.append(CellValue(columnName: column.name, rawValue: nil, dataType: column.udtName))
                    continue
                }

                let cell = randomAccess[index]
                let rawValue: String?

                if cell.bytes == nil {
                    rawValue = nil
                } else {
                    // Try to decode as String — most PG types can cast to text
                    rawValue = try? cell.decode(String.self)
                }

                values.append(CellValue(columnName: column.name, rawValue: rawValue, dataType: column.udtName))
            }

            return TableRow(values: values)
        }
    }
}
