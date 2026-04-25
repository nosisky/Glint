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

        // Build columns from actual SQL result — guarantees alignment with data
        let resultColumns = buildResultColumns(from: rawRows, tableColumns: table.columns)

        // Materialize rows using result column order (not schema order)
        let rows = materializeRows(rawRows, columns: resultColumns)

        let executionTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        return QueryResult(
            rows: rows,
            columns: resultColumns,
            totalCount: totalCount,
            pageSize: pageSize,
            currentOffset: offset,
            executionTimeMs: executionTime,
            query: sql
        )
    }

    // MARK: - Column Discovery

    /// Build ColumnInfo array from the actual SQL result to guarantee
    /// that header columns and data cells are always in the same order.
    private func buildResultColumns(from pgRows: [PostgresRow], tableColumns: [ColumnInfo]) -> [ColumnInfo] {
        guard let firstRow = pgRows.first else { return tableColumns }

        let cells = firstRow.makeRandomAccess()
        var result: [ColumnInfo] = []

        for i in 0..<cells.count {
            let cell = cells[i]
            let name = cell.columnName

            // Enrich with schema metadata if available
            if let meta = tableColumns.first(where: { $0.name == name }) {
                result.append(ColumnInfo(
                    name: name,
                    tableName: meta.tableName,
                    dataType: meta.dataType,
                    udtName: meta.udtName,
                    isNullable: meta.isNullable,
                    isPrimaryKey: meta.isPrimaryKey,
                    hasDefault: meta.hasDefault,
                    defaultValue: meta.defaultValue,
                    characterMaxLength: meta.characterMaxLength,
                    numericPrecision: meta.numericPrecision,
                    ordinalPosition: i
                ))
            } else {
                // Column not in schema metadata (expression, alias, etc.)
                result.append(ColumnInfo(
                    name: name,
                    tableName: "",
                    dataType: "text",
                    udtName: "text",
                    isNullable: true,
                    isPrimaryKey: false,
                    hasDefault: false,
                    defaultValue: nil,
                    characterMaxLength: nil,
                    numericPrecision: nil,
                    ordinalPosition: i
                ))
            }
        }

        return result
    }

    // MARK: - Row Materialization

    /// Convert PostgresNIO rows into our generic TableRow representation.
    /// Iterates through the row's cells directly (not schema columns) to preserve alignment.
    private func materializeRows(_ pgRows: [PostgresRow], columns: [ColumnInfo]) -> [TableRow] {
        pgRows.map { pgRow in
            let randomAccess = pgRow.makeRandomAccess()
            var values: [CellValue] = []

            for i in 0..<randomAccess.count {
                let cell = randomAccess[i]
                let colInfo = columns.indices.contains(i) ? columns[i] : nil
                let rawValue: String?

                if cell.bytes == nil {
                    rawValue = nil
                } else {
                    rawValue = try? cell.decode(String.self)
                }

                values.append(CellValue(
                    columnName: cell.columnName,
                    rawValue: rawValue,
                    dataType: colInfo?.udtName ?? "text"
                ))
            }

            return TableRow(values: values)
        }
    }
}
