import Foundation
import PostgresNIO

/// Service that introspects PostgreSQL catalogs to build schema metadata.
/// Queries `information_schema` and `pg_catalog` for databases, tables, columns, and constraints.
actor SchemaIntrospector {
    private let connection: PostgresConnection

    init(connection: PostgresConnection) {
        self.connection = connection
    }

    // MARK: - Database Listing

    /// Fetch all databases on the server (excluding templates).
    func fetchDatabases() async throws -> [String] {
        let sql = """
            SELECT datname
            FROM pg_catalog.pg_database
            WHERE datistemplate = false
              AND datallowconn = true
            ORDER BY datname
            """

        let rows = try await connection.queryAll(sql)
        return rows.compactMap { row -> String? in
            let cols = row.makeRandomAccess()
            return try? cols[0].decode(String.self)
        }
    }

    // MARK: - Schema Introspection

    /// Fetch all schemas in the database (excluding system schemas).
    func fetchSchemas() async throws -> [DatabaseSchemaInfo] {
        let sql = """
            SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
            ORDER BY schema_name
            """

        let rows = try await connection.queryAll(sql)
        return rows.compactMap { row -> DatabaseSchemaInfo? in
            let randomAccess = row.makeRandomAccess()
            guard let name = try? randomAccess[0].decode(String.self) else { return nil }
            return DatabaseSchemaInfo(name: name)
        }
    }

    /// Fetch all tables (and views) for a given schema.
    func fetchTables(schema: String = "public") async throws -> [TableInfo] {
        let sql = """
            SELECT
                t.table_schema,
                t.table_name,
                t.table_type,
                COALESCE(c.reltuples::bigint, 0) as estimated_rows
            FROM information_schema.tables t
            LEFT JOIN pg_catalog.pg_class c
                ON c.relname = t.table_name
                AND c.relnamespace = (
                    SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = t.table_schema
                )
            WHERE t.table_schema = '\(schema)'
            ORDER BY t.table_name
            """

        let rows = try await connection.queryAll(sql)
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

            return TableInfo(
                schema: tableSchema,
                name: tableName,
                type: tableType,
                estimatedRowCount: estimatedRows
            )
        }
    }

    /// Fetch column metadata for a specific table.
    func fetchColumns(schema: String, table: String) async throws -> [ColumnInfo] {
        let sql = """
            SELECT
                c.column_name,
                c.data_type,
                c.udt_name,
                c.is_nullable,
                c.column_default,
                c.character_maximum_length,
                c.numeric_precision,
                c.ordinal_position,
                CASE WHEN pk.column_name IS NOT NULL THEN true ELSE false END as is_primary_key
            FROM information_schema.columns c
            LEFT JOIN (
                SELECT ku.column_name, ku.table_schema, ku.table_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage ku
                    ON tc.constraint_name = ku.constraint_name
                    AND tc.table_schema = ku.table_schema
                WHERE tc.constraint_type = 'PRIMARY KEY'
            ) pk ON pk.column_name = c.column_name
                AND pk.table_schema = c.table_schema
                AND pk.table_name = c.table_name
            WHERE c.table_schema = '\(schema)'
              AND c.table_name = '\(table)'
            ORDER BY c.ordinal_position
            """

        let rows = try await connection.queryAll(sql)
        return rows.compactMap { row -> ColumnInfo? in
            let cols = row.makeRandomAccess()
            guard let columnName = try? cols[0].decode(String.self),
                  let dataType = try? cols[1].decode(String.self),
                  let udtName = try? cols[2].decode(String.self),
                  let isNullableRaw = try? cols[3].decode(String.self),
                  let ordinalPosition = try? cols[7].decode(Int.self),
                  let isPrimaryKey = try? cols[8].decode(Bool.self)
            else { return nil }

            let columnDefault = try? cols[4].decode(String?.self)
            let charMaxLength = try? cols[5].decode(Int?.self)
            let numericPrecision = try? cols[6].decode(Int?.self)

            return ColumnInfo(
                name: columnName,
                tableName: table,
                dataType: dataType,
                udtName: udtName,
                isNullable: isNullableRaw == "YES",
                isPrimaryKey: isPrimaryKey,
                hasDefault: columnDefault != nil,
                defaultValue: columnDefault ?? nil,
                characterMaxLength: charMaxLength ?? nil,
                numericPrecision: numericPrecision ?? nil,
                ordinalPosition: ordinalPosition
            )
        }
    }

    /// Fetch all tables with their columns, enums, and FKs for a schema.
    func fetchFullSchema(schema: String = "public") async throws -> DatabaseSchemaInfo {
        var tables = try await fetchTables(schema: schema)
        let enums = try await fetchEnumTypes()
        let foreignKeys = try await fetchForeignKeys(schema: schema)

        for i in tables.indices {
            var columns = try await fetchColumns(schema: schema, table: tables[i].name)

            // Enrich with enum values
            for j in columns.indices {
                if columns[j].dataType.lowercased() == "user-defined" {
                    if let values = enums[columns[j].udtName] {
                        columns[j].enumValues = values
                    }
                }
            }

            // Enrich with FK references
            let tableFKs = foreignKeys.filter { $0.tableName == tables[i].name }
            for fk in tableFKs {
                if let j = columns.firstIndex(where: { $0.name == fk.columnName }) {
                    columns[j].foreignKey = ForeignKeyRef(
                        constraintName: fk.constraintName,
                        referencedTable: fk.referencedTable,
                        referencedColumn: fk.referencedColumn
                    )
                }
            }

            tables[i].columns = columns
        }
        return DatabaseSchemaInfo(name: schema, tables: tables)
    }

    // MARK: - Enum Types

    /// Fetch all user-defined enum types and their values.
    func fetchEnumTypes() async throws -> [String: [String]] {
        let sql = """
            SELECT t.typname, e.enumlabel
            FROM pg_type t
            JOIN pg_enum e ON t.oid = e.enumtypid
            ORDER BY t.typname, e.enumsortorder
            """

        let rows = try await connection.queryAll(sql)
        var result: [String: [String]] = [:]
        for row in rows {
            let cols = row.makeRandomAccess()
            guard let typeName = try? cols[0].decode(String.self),
                  let enumLabel = try? cols[1].decode(String.self)
            else { continue }
            result[typeName, default: []].append(enumLabel)
        }
        return result
    }

    // MARK: - Foreign Keys

    /// Intermediate struct for FK introspection results.
    struct FKResult {
        let constraintName: String
        let tableName: String
        let columnName: String
        let referencedTable: String
        let referencedColumn: String
    }

    /// Fetch all foreign key constraints for a schema.
    func fetchForeignKeys(schema: String) async throws -> [FKResult] {
        let sql = """
            SELECT
                tc.constraint_name,
                kcu.table_name,
                kcu.column_name,
                ccu.table_name AS referenced_table,
                ccu.column_name AS referenced_column
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
                AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage ccu
                ON tc.constraint_name = ccu.constraint_name
                AND tc.table_schema = ccu.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND tc.table_schema = '\(schema)'
            ORDER BY kcu.table_name, kcu.column_name
            """

        let rows = try await connection.queryAll(sql)
        return rows.compactMap { row -> FKResult? in
            let cols = row.makeRandomAccess()
            guard let constraintName = try? cols[0].decode(String.self),
                  let tableName = try? cols[1].decode(String.self),
                  let columnName = try? cols[2].decode(String.self),
                  let refTable = try? cols[3].decode(String.self),
                  let refColumn = try? cols[4].decode(String.self)
            else { return nil }
            return FKResult(
                constraintName: constraintName,
                tableName: tableName,
                columnName: columnName,
                referencedTable: refTable,
                referencedColumn: refColumn
            )
        }
    }

    /// Fetch distinct values for a column (for filter popover).
    func fetchDistinctValues(
        schema: String,
        table: String,
        column: String,
        limit: Int = 200
    ) async throws -> [String?] {
        let sql = """
            SELECT DISTINCT "\(column)"::text
            FROM "\(schema)"."\(table)"
            ORDER BY "\(column)"::text
            LIMIT \(limit)
            """

        let rows = try await connection.queryAll(sql)
        return rows.map { row -> String? in
            let cols = row.makeRandomAccess()
            return try? cols[0].decode(String?.self)
        }
    }

    /// Get exact row count for a table.
    func fetchExactRowCount(schema: String, table: String) async throws -> Int64 {
        let sql = "SELECT count(*) FROM \"\(schema)\".\"\(table)\""
        return try await connection.queryScalar(sql)
    }
}
