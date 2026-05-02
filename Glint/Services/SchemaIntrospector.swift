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
            SELECT schema_name 
            FROM information_schema.schemata
            WHERE schema_name != 'pg_toast'
            ORDER BY 
                CASE 
                    WHEN schema_name = 'public' THEN 1
                    WHEN schema_name IN ('pg_catalog', 'information_schema') THEN 3
                    ELSE 2
                END, 
                schema_name
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
            WHERE t.table_schema = \(SQLSanitizer.quoteLiteral(schema))
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
            SELECT
                a.attname AS column_name,
                pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
                t.typname AS udt_name,
                NOT a.attnotnull AS is_nullable,
                pg_get_expr(ad.adbin, ad.adrelid) AS column_default,
                CASE 
                    WHEN a.atttypmod > -1 AND t.typname IN ('varchar', 'bpchar', 'char') THEN a.atttypmod - 4
                    ELSE NULL
                END AS character_maximum_length,
                CASE
                    WHEN a.atttypmod > -1 AND t.typname IN ('numeric', 'decimal') THEN ((a.atttypmod - 4) >> 16) & 65535
                    ELSE NULL
                END AS numeric_precision,
                a.attnum AS ordinal_position,
                CASE WHEN ix.indisprimary THEN true ELSE false END AS is_primary_key
            FROM pg_attribute a
            JOIN pg_class c ON a.attrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            JOIN pg_type t ON a.atttypid = t.oid
            LEFT JOIN pg_attrdef ad ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
            LEFT JOIN pg_index ix ON c.oid = ix.indrelid AND a.attnum = ANY(ix.indkey) AND ix.indisprimary
            WHERE n.nspname = \(SQLSanitizer.quoteLiteral(schema))
              AND c.relname = \(SQLSanitizer.quoteLiteral(table))
              AND a.attnum > 0
              AND NOT a.attisdropped
            ORDER BY a.attnum
            """)

        return rows.compactMap { row -> ColumnInfo? in
            let cols = row.makeRandomAccess()
            let name = try? cols[0].decode(String.self)
            let dataType = try? cols[1].decode(String.self)
            let udtName = try? cols[2].decode(String.self)
            let isNullable = try? cols[3].decode(Bool.self)
            let ordinal = (try? cols[7].decode(Int16.self)).map(Int.init) ?? (try? cols[7].decode(Int.self)) ?? 0
            let isPK = try? cols[8].decode(Bool.self)
            
            guard let name = name, let dataType = dataType, let udtName = udtName, let isNullable = isNullable, let isPK = isPK else {
                print("[Glint] Failed to decode column. name=\(String(describing: name)), type=\(String(describing: dataType))")
                return nil
            }

            return ColumnInfo(
                name: name,
                tableName: table,
                dataType: dataType,
                udtName: udtName,
                isNullable: isNullable,
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
        let functions = try await fetchFunctions(schema: schema)
        let enums = try await fetchEnumTypes()
        let foreignKeys = try await fetchForeignKeys(schema: schema)

        for i in tables.indices {
            var columns = try await fetchColumns(schema: schema, table: tables[i].name)
            enrichWithEnums(&columns, enums: enums)
            enrichWithForeignKeys(&columns, foreignKeys: foreignKeys, tableName: tables[i].name)
            tables[i].columns = columns
        }
        return DatabaseSchemaInfo(name: schema, tables: tables, functions: functions)
    }

    // MARK: - Functions

    func fetchFunctions(schema: String) async throws -> [FunctionInfo] {
        let rows = try await connection.queryAll("""
            SELECT p.proname AS function_name, 
                   pg_get_function_identity_arguments(p.oid) AS arguments, 
                   pg_get_function_result(p.oid) as return_type,
                   e.extname AS extension_name,
                   l.lanname AS language,
                   p.prosrc AS definition,
                   p.proisstrict AS is_strict,
                   p.provolatile AS volatility,
                   p.prosecdef AS is_security_definer
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            JOIN pg_language l ON p.prolang = l.oid
            LEFT JOIN pg_depend d ON d.objid = p.oid AND d.classid = 'pg_proc'::regclass AND d.deptype = 'e'
            LEFT JOIN pg_extension e ON e.oid = d.refobjid AND d.refclassid = 'pg_extension'::regclass
            WHERE n.nspname = \(SQLSanitizer.quoteLiteral(schema))
            ORDER BY p.proname
            """)
        
        return rows.compactMap { row -> FunctionInfo? in
            let cols = row.makeRandomAccess()
            guard let name = try? cols[0].decode(String.self),
                  let args = try? cols[1].decode(String.self),
                  let returnType = try? cols[2].decode(String.self),
                  let language = try? cols[4].decode(String.self),
                  let definition = try? cols[5].decode(String.self),
                  let isStrict = try? cols[6].decode(Bool.self),
                  let volatility = try? cols[7].decode(String.self),
                  let isSecurityDefiner = try? cols[8].decode(Bool.self)
            else { return nil }
            
            let extensionName = try? cols[3].decode(String?.self)
            return FunctionInfo(
                schema: schema, name: name, arguments: args, returnType: returnType,
                extensionName: extensionName, language: language, definition: definition,
                isStrict: isStrict, volatility: volatility, isSecurityDefiner: isSecurityDefiner
            )
        }
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
            WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = \(SQLSanitizer.quoteLiteral(schema))
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
        let qCol = SQLSanitizer.quoteIdentifier(column)
        let qTable = "\(SQLSanitizer.quoteIdentifier(schema)).\(SQLSanitizer.quoteIdentifier(table))"
        let rows = try await connection.queryAll("""
            SELECT DISTINCT \(qCol)::text
            FROM \(qTable)
            ORDER BY \(qCol)::text
            LIMIT \(limit)
            """)
        return rows.map { try? $0.makeRandomAccess()[0].decode(String?.self) }
    }

    // MARK: - Row Count

    func fetchExactRowCount(schema: String, table: String) async throws -> Int64 {
        let qTable = "\(SQLSanitizer.quoteIdentifier(schema)).\(SQLSanitizer.quoteIdentifier(table))"
        return try await connection.queryScalar("SELECT count(*) FROM \(qTable)")
    }

    // MARK: - Indexes

    struct IndexResult: Sendable {
        let name: String
        let isUnique: Bool
        let isPrimary: Bool
        let definition: String
        let columns: [String]
    }

    func fetchIndexes(schema: String, table: String) async throws -> [IndexResult] {
        let rows = try await connection.queryAll("""
            SELECT i.relname AS index_name,
                   ix.indisunique AS is_unique,
                   ix.indisprimary AS is_primary,
                   pg_get_indexdef(ix.indexrelid) AS index_def,
                   array_to_string(ARRAY(
                       SELECT a.attname FROM unnest(ix.indkey) AS k(n)
                       JOIN pg_attribute a ON a.attrelid = ix.indrelid AND a.attnum = k.n
                   ), ',') AS columns
            FROM pg_index ix
            JOIN pg_class i ON i.oid = ix.indexrelid
            JOIN pg_class t ON t.oid = ix.indrelid
            JOIN pg_namespace n ON n.oid = t.relnamespace
            WHERE n.nspname = \(SQLSanitizer.quoteLiteral(schema))
              AND t.relname = \(SQLSanitizer.quoteLiteral(table))
            ORDER BY ix.indisprimary DESC, i.relname
            """)

        return rows.compactMap { row -> IndexResult? in
            let cols = row.makeRandomAccess()
            guard let name = try? cols[0].decode(String.self),
                  let isUnique = try? cols[1].decode(Bool.self),
                  let isPrimary = try? cols[2].decode(Bool.self),
                  let definition = try? cols[3].decode(String.self),
                  let columnStr = try? cols[4].decode(String.self)
            else { return nil }
            return IndexResult(
                name: name, isUnique: isUnique, isPrimary: isPrimary,
                definition: definition,
                columns: columnStr.split(separator: ",").map(String.init)
            )
        }
    }

    // MARK: - Table Metadata

    struct TableMeta: Sendable {
        let tablespace: String
        let isTemporary: Bool
    }

    func fetchTableMeta(schema: String, table: String) async throws -> TableMeta {
        let rows = try await connection.queryAll("""
            SELECT COALESCE(t.tablespace, 'pg_default') AS tablespace,
                   c.relpersistence = 't' AS is_temporary
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
            WHERE n.nspname = \(SQLSanitizer.quoteLiteral(schema))
              AND c.relname = \(SQLSanitizer.quoteLiteral(table))
            """)
        guard let row = rows.first else {
            return TableMeta(tablespace: "pg_default", isTemporary: false)
        }
        let cols = row.makeRandomAccess()
        let tablespace = (try? cols[0].decode(String.self)) ?? "pg_default"
        let isTemporary = (try? cols[1].decode(Bool.self)) ?? false
        return TableMeta(tablespace: tablespace, isTemporary: isTemporary)
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
