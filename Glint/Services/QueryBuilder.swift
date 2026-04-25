import Foundation

/// Compiles an array of `FilterConstraint` objects into a parameterized SQL WHERE clause.
/// This is the core of the No-SQL filter engine — translates UI clicks into SQL.
struct QueryBuilder: Sendable {

    /// Build a complete SELECT query with filters, pagination, and ordering.
    func buildQuery(
        table: TableInfo,
        filters: [FilterConstraint],
        globalSearch: String?,
        orderBy: String? = nil,
        ascending: Bool = true,
        limit: Int = 200,
        offset: Int = 0
    ) -> (sql: String, countSQL: String) {
        let qualifiedTable = table.qualifiedName

        // Build WHERE clause from constraints
        var conditions: [String] = []

        // Add filter constraints
        for filter in filters {
            if let condition = buildCondition(filter) {
                conditions.append(condition)
            }
        }

        // Add global search
        if let search = globalSearch, !search.isEmpty {
            let searchCondition = buildGlobalSearch(search, columns: table.columns)
            if !searchCondition.isEmpty {
                conditions.append("(\(searchCondition))")
            }
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"

        let orderClause: String
        if let orderBy {
            let direction = ascending ? "ASC" : "DESC"
            orderClause = "ORDER BY \"\(orderBy)\" \(direction) NULLS LAST"
        } else {
            // Default: order by primary key or first column
            if let pk = table.columns.first(where: { $0.isPrimaryKey }) {
                orderClause = "ORDER BY \"\(pk.name)\" ASC"
            } else {
                orderClause = "ORDER BY 1 ASC"
            }
        }

        // Build SELECT list — cast every column to text so PG formats values
        // for us (timestamps, bigints, booleans, etc.) instead of binary wire format.
        // AS alias preserves the original column name in the result.
        let selectColumns = table.columns.map { col in
            "\"\(col.name)\"::text AS \"\(col.name)\""
        }.joined(separator: ", ")

        // Fallback: if no columns known, use *
        let selectList = table.columns.isEmpty ? "*" : selectColumns

        let sql = """
            SELECT \(selectList) FROM \(qualifiedTable)
            \(whereClause)
            \(orderClause)
            LIMIT \(limit) OFFSET \(offset)
            """

        let countSQL = """
            SELECT count(*) FROM \(qualifiedTable)
            \(whereClause)
            """

        return (sql.trimmingCharacters(in: .whitespacesAndNewlines), countSQL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Condition Builders

    private func buildCondition(_ filter: FilterConstraint) -> String? {
        let col = "\"\(filter.columnName)\""

        switch filter.operation {
        case .equals:
            switch filter.value {
            case .text(let v):
                return "\(col) = \(escapeString(v))"
            case .number(let v):
                return "\(col) = \(v)"
            case .boolean(let v):
                return "\(col) = \(v)"
            default:
                return nil
            }

        case .notEquals:
            switch filter.value {
            case .text(let v):
                return "\(col) != \(escapeString(v))"
            case .number(let v):
                return "\(col) != \(v)"
            default:
                return nil
            }

        case .contains:
            if case .text(let v) = filter.value {
                return "\(col)::text ILIKE \(escapeString("%\(escapeLike(v))%"))"
            }
            return nil

        case .startsWith:
            if case .text(let v) = filter.value {
                return "\(col)::text ILIKE \(escapeString("\(escapeLike(v))%"))"
            }
            return nil

        case .endsWith:
            if case .text(let v) = filter.value {
                return "\(col)::text ILIKE \(escapeString("%\(escapeLike(v))"))"
            }
            return nil

        case .greaterThan:
            switch filter.value {
            case .number(let v): return "\(col) > \(v)"
            case .date(let d): return "\(col) > \(escapeString(d.ISO8601Format()))"
            default: return nil
            }

        case .lessThan:
            switch filter.value {
            case .number(let v): return "\(col) < \(v)"
            case .date(let d): return "\(col) < \(escapeString(d.ISO8601Format()))"
            default: return nil
            }

        case .greaterOrEqual:
            switch filter.value {
            case .number(let v): return "\(col) >= \(v)"
            default: return nil
            }

        case .lessOrEqual:
            switch filter.value {
            case .number(let v): return "\(col) <= \(v)"
            default: return nil
            }

        case .between:
            switch filter.value {
            case .range(let lo, let hi):
                return "\(col) BETWEEN \(lo) AND \(hi)"
            case .dateRange(let from, let to):
                return "\(col) BETWEEN \(escapeString(from.ISO8601Format())) AND \(escapeString(to.ISO8601Format()))"
            default:
                return nil
            }

        case .isNull:
            return "\(col) IS NULL"

        case .isNotNull:
            return "\(col) IS NOT NULL"

        case .inList:
            if case .list(let items) = filter.value {
                let escaped = items.map { escapeString($0) }.joined(separator: ", ")
                return "\(col) IN (\(escaped))"
            }
            return nil
        }
    }

    /// Build global search: ILIKE OR across all text-searchable and castable columns.
    private func buildGlobalSearch(_ searchText: String, columns: [ColumnInfo]) -> String {
        let escapedSearch = escapeLike(searchText)
        let pattern = escapeString("%\(escapedSearch)%")

        var clauses: [String] = []

        for column in columns {
            if column.isTextSearchable {
                clauses.append("\"\(column.name)\" ILIKE \(pattern)")
            } else if column.isNumeric {
                // Cast numeric to text for partial matching
                clauses.append("\"\(column.name)\"::text ILIKE \(pattern)")
            }
        }

        return clauses.joined(separator: " OR ")
    }

    // MARK: - SQL Safety

    /// Escape a string value for SQL (single-quote wrapping with escaping).
    private func escapeString(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }

    /// Escape LIKE special characters.
    private func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
