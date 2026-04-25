import Foundation

struct DatabaseSchemaInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var tables: [TableInfo]

    init(name: String, tables: [TableInfo] = []) {
        self.id = name
        self.name = name
        self.tables = tables
    }
}

struct TableInfo: Identifiable, Hashable, Sendable {
    var id: String { "\(schema).\(name)" }
    let schema: String
    let name: String
    let type: TableType
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

    var qualifiedName: String { "\"\(schema)\".\"\(name)\"" }
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

struct ColumnInfo: Identifiable, Hashable, Sendable {
    var id: String { "\(tableName).\(name)" }
    let name: String
    let tableName: String
    let dataType: String
    let udtName: String
    let isNullable: Bool
    let isPrimaryKey: Bool
    let hasDefault: Bool
    let defaultValue: String?
    let characterMaxLength: Int?
    let numericPrecision: Int?
    let ordinalPosition: Int

    var enumValues: [String]?
    var foreignKey: ForeignKeyRef?

    var isTextSearchable: Bool {
        let types: Set<String> = ["varchar", "text", "char", "bpchar", "name", "character varying", "character", "citext", "uuid"]
        return types.contains(udtName.lowercased()) || types.contains(dataType.lowercased())
    }

    var isNumeric: Bool {
        let types: Set<String> = [
            "int2", "int4", "int8", "float4", "float8", "numeric", "decimal",
            "smallint", "integer", "bigint", "real", "double precision",
            "serial", "bigserial", "smallserial", "money"
        ]
        return types.contains(udtName.lowercased()) || types.contains(dataType.lowercased())
    }

    var isTemporal: Bool {
        let types: Set<String> = ["date", "time", "timetz", "timestamp", "timestamptz", "interval"]
        return types.contains(udtName.lowercased())
    }

    var isBoolean: Bool {
        udtName.lowercased() == "bool" || dataType.lowercased() == "boolean"
    }

    var isEnum: Bool {
        dataType.lowercased() == "user-defined" && enumValues != nil
    }

    var isForeignKey: Bool { foreignKey != nil }

    var typeLabel: String {
        if isEnum { return udtName }
        if let maxLen = characterMaxLength { return "\(udtName)(\(maxLen))" }
        return udtName
    }
}

struct ForeignKeyRef: Hashable, Sendable {
    let constraintName: String
    let referencedTable: String
    let referencedColumn: String
}
