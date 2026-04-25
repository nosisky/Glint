import Foundation

/// Maps PostgreSQL type names to display-friendly descriptions and Swift type associations.
struct PostgresTypeMapper: Sendable {
    
    static func displayName(for udtName: String) -> String {
        switch udtName.lowercased() {
        case "int2": "smallint"
        case "int4": "integer"
        case "int8": "bigint"
        case "float4": "real"
        case "float8": "double precision"
        case "bool": "boolean"
        case "varchar": "varchar"
        case "bpchar": "char"
        case "timestamptz": "timestamp with tz"
        case "timetz": "time with tz"
        default: udtName
        }
    }

    static func isEditable(udtName: String) -> Bool {
        let nonEditable: Set<String> = ["bytea", "tsvector", "tsquery", "xml"]
        return !nonEditable.contains(udtName.lowercased())
    }
}
