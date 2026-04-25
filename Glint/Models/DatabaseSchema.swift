import Foundation

/// Represents a PostgreSQL schema (e.g., "public").
struct DatabaseSchemaInfo: Identifiable, Hashable, Sendable {
    let id: String // schema name is the identity
    let name: String
    var tables: [TableInfo]

    init(name: String, tables: [TableInfo] = []) {
        self.id = name
        self.name = name
        self.tables = tables
    }
}

/// Represents a single table within a schema.
struct TableInfo: Identifiable, Hashable, Sendable {
    var id: String { "\(schema).\(name)" }
    let schema: String
    let name: String
    let type: TableType // table, view, materialized view
    var columns: [ColumnInfo]
    var estimatedRowCount: Int64?

    init(
        schema: String = "public",
        name: String,
        type: TableType = .table,
        columns: [ColumnInfo] = [],
        estimatedRowCount: Int64? = nil
    ) {
        self.schema = schema
        self.name = name
        self.type = type
        self.columns = columns
        self.estimatedRowCount = estimatedRowCount
    }

    /// Fully qualified name: "schema"."table"
    var qualifiedName: String {
        "\"\(schema)\".\"\(name)\""
    }
}

enum TableType: String, Hashable, Sendable {
    case table = "BASE TABLE"
    case view = "VIEW"
    case materializedView = "MATERIALIZED VIEW"

    var icon: String {
        switch self {
        case .table: "tablecells"
        case .view: "eye"
        case .materializedView: "square.stack.3d.up"
        }
    }
}

/// Represents a single column within a table.
struct ColumnInfo: Identifiable, Hashable, Sendable {
    var id: String { "\(tableName).\(name)" }
    let name: String
    let tableName: String
    let dataType: String        // raw PG type name (e.g., "character varying")
    let udtName: String         // underlying type (e.g., "varchar", "int4")
    let isNullable: Bool
    let isPrimaryKey: Bool
    let hasDefault: Bool
    let defaultValue: String?
    let characterMaxLength: Int?
    let numericPrecision: Int?
    let ordinalPosition: Int

    // Schema intelligence
    var enumValues: [String]?        // populated for enum types
    var foreignKey: ForeignKeyRef?   // populated for FK columns

    /// Whether this column is text-searchable (for global search ILIKE).
    var isTextSearchable: Bool {
        let textTypes: Set<String> = [
            "varchar", "text", "char", "bpchar", "name",
            "character varying", "character", "citext", "uuid"
        ]
        return textTypes.contains(udtName.lowercased())
            || textTypes.contains(dataType.lowercased())
    }

    /// Whether this column is numeric (for range filters).
    var isNumeric: Bool {
        let numericTypes: Set<String> = [
            "int2", "int4", "int8", "float4", "float8",
            "numeric", "decimal", "smallint", "integer",
            "bigint", "real", "double precision", "serial",
            "bigserial", "smallserial", "money"
        ]
        return numericTypes.contains(udtName.lowercased())
            || numericTypes.contains(dataType.lowercased())
    }

    /// Whether this column is a date/time type.
    var isTemporal: Bool {
        let temporalTypes: Set<String> = [
            "date", "time", "timetz", "timestamp", "timestamptz",
            "interval"
        ]
        return temporalTypes.contains(udtName.lowercased())
    }

    /// Whether this column is boolean.
    var isBoolean: Bool {
        udtName.lowercased() == "bool" || dataType.lowercased() == "boolean"
    }

    /// Whether this is a user-defined enum type.
    var isEnum: Bool {
        dataType.lowercased() == "user-defined" && enumValues != nil
    }

    /// Whether this column has a foreign key reference.
    var isForeignKey: Bool { foreignKey != nil }

    /// Human-readable type label for display.
    var typeLabel: String {
        if isEnum { return udtName }
        if let maxLen = characterMaxLength {
            return "\(udtName)(\(maxLen))"
        }
        return udtName
    }
}

/// Foreign key reference to another table's column.
struct ForeignKeyRef: Hashable, Sendable {
    let constraintName: String
    let referencedTable: String
    let referencedColumn: String
}
