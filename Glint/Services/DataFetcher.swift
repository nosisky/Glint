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

        let (sql, countSQL) = queryBuilder.buildQuery(
            table: table,
            filters: filters,
            globalSearch: globalSearch,
            orderBy: orderBy,
            ascending: ascending,
            limit: pageSize,
            offset: offset
        )

        let totalCount = try await connection.queryScalar(countSQL)
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
                let rawValue: String? = cell.bytes == nil ? nil : (try? cell.decode(String.self))
                let dataType = columns.indices.contains(i) ? columns[i].udtName : "text"
                return CellValue(columnName: cell.columnName, rawValue: rawValue, dataType: dataType)
            }
            return TableRow(values: values)
        }
    }
}
