import Foundation
import PostgresNIO

actor SchemaIntrospector {
    private let connection: PostgresConnection

    init(connection: PostgresConnection) {
        self.connection = connection
    }

    // MARK: - Databases

    func fetchDatabases() async throws -> [String] {
        let rows = try await connection.queryAll("""
            SELECT datname FROM pg_catalog.pg_database
            WHERE datistemplate = false AND datallowconn = true
            ORDER BY datname
            """)
        return rows.compactMap { try? $0.makeRandomAccess()[0].decode(String.self) }
    }

    // MARK: - Schemas

    func fetchSchemas() async throws -> [DatabaseSchemaInfo] {
        let rows = try await connection.queryAll("""
            SELECT schema_name FROM information_schema.schemata
            WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
            ORDER BY schema_name
            """)
        return rows.compactMap {
            guard let name = try? $0.makeRandomAccess()[0].decode(String.self) else { return nil }
            return DatabaseSchemaInfo(name: name)
        }
    }

    // MARK: - Tables

    func fetchTables(schema: String = "public") async throws -> [TableInfo] {
        let rows = try await connection.queryAll("""
            SELECT t.table_schema, t.table_name, t.table_type,
                   COALESCE(c.reltuples::bigint, 0) as estimated_rows
            FROM information_schema.tables t
            LEFT JOIN pg_catalog.pg_class c
                ON c.relname = t.table_name
                AND c.relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = t.table_schema)
            WHERE t.table_schema = '\(schema)'
            ORDER BY t.table_name
            """)

        return rows.compactMap { row -> TableInfo? in
            let cols = row.makeRandomAccess()
            guard let tableSchema = try? cols[0].decode(String.self),
                  let tableName = try? cols[1].decode(String.self),
                  let tableTypeRaw = try? cols[2].decode(String.self),
                  let estimatedRows = try? cols[3].decode(Int64.self)
            else { return nil }

            let tableType: TableType = switch tableTypeRaw {
            case "VIEW": .view
            case "MATERIALIZED VIEW": .materializedView
            default: .table
            }

            return TableInfo(schema: tableSchema, name: tableName, type: tableType, estimatedRowCount: estimatedRows)
        }
    }

    // MARK: - Columns

    func fetchColumns(schema: String, table: String) async throws -> [ColumnInfo] {
        let rows = try await connection.queryAll("""
            SELECT c.column_name, c.data_type, c.udt_name, c.is_nullable,
                   c.column_default, c.character_maximum_length, c.numeric_precision,
                   c.ordinal_position,
                   CASE WHEN pk.column_name IS NOT NULL THEN true ELSE false END as is_primary_key
            FROM information_schema.columns c
            LEFT JOIN (
                SELECT ku.column_name, ku.table_schema, ku.table_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage ku
                    ON tc.constraint_name = ku.constraint_name AND tc.table_schema = ku.table_schema
                WHERE tc.constraint_type = 'PRIMARY KEY'
            ) pk ON pk.column_name = c.column_name
                AND pk.table_schema = c.table_schema AND pk.table_name = c.table_name
            WHERE c.table_schema = '\(schema)' AND c.table_name = '\(table)'
            ORDER BY c.ordinal_position
            """)

        return rows.compactMap { row -> ColumnInfo? in
            let cols = row.makeRandomAccess()
            guard let name = try? cols[0].decode(String.self),
                  let dataType = try? cols[1].decode(String.self),
                  let udtName = try? cols[2].decode(String.self),
                  let isNullableRaw = try? cols[3].decode(String.self),
                  let ordinal = try? cols[7].decode(Int.self),
                  let isPK = try? cols[8].decode(Bool.self)
            else { return nil }

            return ColumnInfo(
                name: name,
                tableName: table,
                dataType: dataType,
                udtName: udtName,
                isNullable: isNullableRaw == "YES",
                isPrimaryKey: isPK,
                hasDefault: (try? cols[4].decode(String?.self)) != nil,
                defaultValue: try? cols[4].decode(String?.self),
                characterMaxLength: try? cols[5].decode(Int?.self),
                numericPrecision: try? cols[6].decode(Int?.self),
                ordinalPosition: ordinal
            )
        }
    }

    // MARK: - Full Schema (with enum + FK enrichment)

    func fetchFullSchema(schema: String = "public") async throws -> DatabaseSchemaInfo {
        var tables = try await fetchTables(schema: schema)
        let enums = try await fetchEnumTypes()
        let foreignKeys = try await fetchForeignKeys(schema: schema)

        for i in tables.indices {
            var columns = try await fetchColumns(schema: schema, table: tables[i].name)
            enrichWithEnums(&columns, enums: enums)
            enrichWithForeignKeys(&columns, foreignKeys: foreignKeys, tableName: tables[i].name)
            tables[i].columns = columns
        }
        return DatabaseSchemaInfo(name: schema, tables: tables)
    }

    // MARK: - Enum Types

    func fetchEnumTypes() async throws -> [String: [String]] {
        let rows = try await connection.queryAll("""
            SELECT t.typname, e.enumlabel
            FROM pg_type t
            JOIN pg_enum e ON t.oid = e.enumtypid
            ORDER BY t.typname, e.enumsortorder
            """)

        var result: [String: [String]] = [:]
        for row in rows {
            let cols = row.makeRandomAccess()
            guard let typeName = try? cols[0].decode(String.self),
                  let label = try? cols[1].decode(String.self)
            else { continue }
            result[typeName, default: []].append(label)
        }
        return result
    }

    // MARK: - Foreign Keys

    struct FKResult {
        let constraintName: String
        let tableName: String
        let columnName: String
        let referencedTable: String
        let referencedColumn: String
    }

    func fetchForeignKeys(schema: String) async throws -> [FKResult] {
        let rows = try await connection.queryAll("""
            SELECT tc.constraint_name, kcu.table_name, kcu.column_name,
                   ccu.table_name AS referenced_table, ccu.column_name AS referenced_column
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage ccu
                ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = '\(schema)'
            ORDER BY kcu.table_name, kcu.column_name
            """)

        return rows.compactMap { row -> FKResult? in
            let cols = row.makeRandomAccess()
            guard let constraint = try? cols[0].decode(String.self),
                  let table = try? cols[1].decode(String.self),
                  let column = try? cols[2].decode(String.self),
                  let refTable = try? cols[3].decode(String.self),
                  let refColumn = try? cols[4].decode(String.self)
            else { return nil }
            return FKResult(constraintName: constraint, tableName: table, columnName: column,
                            referencedTable: refTable, referencedColumn: refColumn)
        }
    }

    // MARK: - Distinct Values

    func fetchDistinctValues(schema: String, table: String, column: String, limit: Int = 200) async throws -> [String?] {
        let rows = try await connection.queryAll("""
            SELECT DISTINCT "\(column)"::text
            FROM "\(schema)"."\(table)"
            ORDER BY "\(column)"::text
            LIMIT \(limit)
            """)
        return rows.map { try? $0.makeRandomAccess()[0].decode(String?.self) }
    }

    // MARK: - Row Count

    func fetchExactRowCount(schema: String, table: String) async throws -> Int64 {
        try await connection.queryScalar("SELECT count(*) FROM \"\(schema)\".\"\(table)\"")
    }

    // MARK: - Enrichment Helpers

    private func enrichWithEnums(_ columns: inout [ColumnInfo], enums: [String: [String]]) {
        for i in columns.indices where columns[i].dataType.lowercased() == "user-defined" {
            columns[i].enumValues = enums[columns[i].udtName]
        }
    }

    private func enrichWithForeignKeys(_ columns: inout [ColumnInfo], foreignKeys: [FKResult], tableName: String) {
        for fk in foreignKeys where fk.tableName == tableName {
            if let i = columns.firstIndex(where: { $0.name == fk.columnName }) {
                columns[i].foreignKey = ForeignKeyRef(
                    constraintName: fk.constraintName,
                    referencedTable: fk.referencedTable,
                    referencedColumn: fk.referencedColumn
                )
            }
        }
    }
}
