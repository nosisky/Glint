//
//  DataFetcher.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

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

        // Use estimated count for unfiltered queries to avoid O(N) full table scans
        let totalCount: Int64
        if hasFilters {
            totalCount = try await connection.queryScalar(countSQL)
        } else {
            totalCount = try await estimatedRowCount(schema: table.schema, table: table.name)
        }

        let rawRows = try await connection.queryAll(sql)
        let resultColumns = buildResultColumns(from: rawRows, tableColumns: table.columns)
        let rows = Self.materializeRows(rawRows, columns: resultColumns)
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

    /// Retrieves a fast row count estimate using pg_class statistics.
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
    func fetchTablePage(table: TableInfo, limit: Int, offset: Int) async throws -> QueryResult {
        let safeSchema = SQLSanitizer.quoteIdentifier(table.schema)
        let safeTable = SQLSanitizer.quoteIdentifier(table.name)

        var orderBy = ""
        if let pk = table.columns.first(where: { $0.isPrimaryKey }) {
            orderBy = "ORDER BY \(SQLSanitizer.quoteIdentifier(pk.name)) ASC"
        }

        let query = "SELECT * FROM \(safeSchema).\(safeTable) \(orderBy) LIMIT \(limit) OFFSET \(offset)"
        
        let pgRows = try await connection.queryAll(query)
        
        let columns: [ColumnInfo]
        if table.columns.isEmpty && !pgRows.isEmpty {
            let cells = pgRows[0].makeRandomAccess()
            columns = (0..<cells.count).map { i in
                ColumnInfo(
                    name: cells[i].columnName,
                    tableName: table.name,
                    dataType: "text",
                    udtName: "text",
                    isNullable: true,
                    isPrimaryKey: false,
                    hasDefault: false,
                    defaultValue: nil,
                    characterMaxLength: nil,
                    numericPrecision: nil,
                    ordinalPosition: i
                )
            }
        } else {
            columns = table.columns
        }
        
        let totalCount = try await estimatedRowCount(schema: table.schema, table: table.name)
        
        let tableRows = Self.materializeRows(pgRows, columns: columns)
        // Note: Execution time isn't strictly tracked here as it's an internal fetch, defaulting to 0
        return QueryResult(
            rows: tableRows,
            columns: columns,
            totalCount: totalCount,
            pageSize: limit,
            currentOffset: offset,
            executionTimeMs: 0,
            query: query
        )
    }
    static func materializeRows(_ pgRows: [PostgresRow], columns: [ColumnInfo]) -> [TableRow] {
        return pgRows.map { pgRow in
            let cells = pgRow.makeRandomAccess()
            var values: [CellValue] = []
            var xmin: String? = nil
            
            for i in 0..<cells.count {
                let cell = cells[i]
                if cell.columnName == "xmin" {
                    xmin = decodeCell(cell)
                    continue
                }
                
                let rawValue = decodeCell(cell)
                let dataType = columns.first(where: { $0.name == cell.columnName })?.udtName ?? "unknown"
                values.append(CellValue(columnName: cell.columnName, rawValue: rawValue, dataType: dataType))
            }
            return TableRow(xmin: xmin, values: values)
        }
    }

    static func decodeCell(_ cell: PostgresCell) -> String? {
        guard var bytes = cell.bytes else { return nil }

        // Attempt strong typed decoding based on PostgresDataType
        switch cell.dataType {
        case .bool:
            return (try? cell.decode(Bool.self)) == true ? "true" : "false"
        case .int2:
            if let v = try? cell.decode(Int16.self) { return String(v) }
        case .int4:
            if let v = try? cell.decode(Int32.self) { return String(v) }
        case .int8:
            if let v = try? cell.decode(Int64.self) { return String(v) }
        case .float4:
            if let v = try? cell.decode(Float.self) { return String(v) }
        case .float8:
            if let v = try? cell.decode(Double.self) { return String(v) }
        case .numeric:
            if let v = try? cell.decode(Decimal.self) { return "\(v)" }
        case .uuid:
            if let v = try? cell.decode(UUID.self) { return v.uuidString }
        case .date:
            if let v = try? cell.decode(Date.self) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                return formatter.string(from: v)
            }
        case .timestamp, .timestamptz:
            if let v = try? cell.decode(Date.self) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.string(from: v)
            }
        case .jsonb:
            // JSONB binary format starts with version 1 byte
            if bytes.readableBytes > 0 {
                let version = bytes.readInteger(as: UInt8.self)
                if version == 1 {
                    return bytes.readString(length: bytes.readableBytes)
                }
            }
        default:
            break
        }

        // Standard string fallback for text, varchar, json, enums, etc.
        if let str = try? cell.decode(String.self) {
            return str
        }
        
        // Final ultimate fallback: just read whatever bytes are left as UTF-8
        return bytes.readString(length: bytes.readableBytes)
    }
}
