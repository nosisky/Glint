import Foundation
import PostgresNIO

actor DataFetcher {
    private let connection: PostgresConnection
    private let queryBuilder = QueryBuilder()

    init(connection: PostgresConnection) {
        self.connection = connection
    }

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
        let hasFilters = !filters.isEmpty || (globalSearch != nil && !globalSearch!.isEmpty)

        let (sql, countSQL) = queryBuilder.buildQuery(
            table: table,
            filters: filters,
            globalSearch: globalSearch,
            orderBy: orderBy,
            ascending: ascending,
            limit: pageSize,
            offset: offset
        )

        // PERF-01: Use estimated count for unfiltered views to avoid O(n) COUNT(*)
        let totalCount: Int64
        if hasFilters {
            totalCount = try await connection.queryScalar(countSQL)
        } else {
            totalCount = try await estimatedRowCount(schema: table.schema, table: table.name)
        }

        let rawRows = try await connection.queryAll(sql)
        let resultColumns = buildResultColumns(from: rawRows, tableColumns: table.columns)
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

    /// PERF-01: Fast row count estimate from pg_class statistics.
    /// Falls back to COUNT(*) if the estimate is unavailable or stale (0 or negative).
    private func estimatedRowCount(schema: String, table: String) async throws -> Int64 {
        let qSchema = SQLSanitizer.quoteLiteral(schema)
        let qTable = SQLSanitizer.quoteLiteral(table)
        let estimate = try await connection.queryScalar("""
            SELECT GREATEST(c.reltuples::bigint, 0)
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = \(qSchema) AND c.relname = \(qTable)
            """)
        // If the estimate is 0 (never analyzed) or negative, fall back to exact count
        if estimate <= 0 {
            let qualifiedTable = "\(SQLSanitizer.quoteIdentifier(schema)).\(SQLSanitizer.quoteIdentifier(table))"
            return try await connection.queryScalar("SELECT count(*) FROM \(qualifiedTable)")
        }
        return estimate
    }

    // MARK: - Column Discovery

    private func buildResultColumns(from pgRows: [PostgresRow], tableColumns: [ColumnInfo]) -> [ColumnInfo] {
        guard let firstRow = pgRows.first else { return tableColumns }

        let cells = firstRow.makeRandomAccess()
        return (0..<cells.count).map { i in
            let name = cells[i].columnName
            if let meta = tableColumns.first(where: { $0.name == name }) {
                return ColumnInfo(
                    name: name, tableName: meta.tableName,
                    dataType: meta.dataType, udtName: meta.udtName,
                    isNullable: meta.isNullable, isPrimaryKey: meta.isPrimaryKey,
                    hasDefault: meta.hasDefault, defaultValue: meta.defaultValue,
                    characterMaxLength: meta.characterMaxLength,
                    numericPrecision: meta.numericPrecision,
                    ordinalPosition: i
                )
            }
            return ColumnInfo(
                name: name, tableName: "", dataType: "text", udtName: "text",
                isNullable: true, isPrimaryKey: false, hasDefault: false,
                defaultValue: nil, characterMaxLength: nil, numericPrecision: nil,
                ordinalPosition: i
            )
        }
    }

    // MARK: - Row Materialization

    private func materializeRows(_ pgRows: [PostgresRow], columns: [ColumnInfo]) -> [TableRow] {
        pgRows.map { pgRow in
            let cells = pgRow.makeRandomAccess()
            let values = (0..<cells.count).map { i -> CellValue in
                let cell = cells[i]
                let rawValue: String?
                if var bytes = cell.bytes {
      
                    if let str = try? cell.decode(String.self) {
                        rawValue = str
                    } else {
                        rawValue = bytes.readString(length: bytes.readableBytes)
                    }
                } else {
                    rawValue = nil
                }
                let dataType = columns.indices.contains(i) ? columns[i].udtName : "text"
                return CellValue(columnName: cell.columnName, rawValue: rawValue, dataType: dataType)
            }
            return TableRow(values: values)
        }
    }
}
