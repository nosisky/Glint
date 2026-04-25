import Foundation

struct QueryBuilder: Sendable {

    func buildQuery(
        table: TableInfo,
        filters: [FilterConstraint],
        globalSearch: String?,
        orderBy: String? = nil,
        ascending: Bool = true,
        limit: Int = 200,
        offset: Int = 0
    ) -> (sql: String, countSQL: String) {
        var conditions: [String] = []

        for filter in filters {
            if let condition = buildCondition(filter) {
                conditions.append(condition)
            }
        }

        if let search = globalSearch, !search.isEmpty {
            let searchCondition = buildGlobalSearch(search, columns: table.columns)
            if !searchCondition.isEmpty {
                conditions.append("(\(searchCondition))")
            }
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"

        let orderClause: String
        if let orderBy {
            orderClause = "ORDER BY \"\(orderBy)\" \(ascending ? "ASC" : "DESC") NULLS LAST"
        } else if let pk = table.columns.first(where: { $0.isPrimaryKey }) {
            orderClause = "ORDER BY \"\(pk.name)\" ASC"
        } else {
            orderClause = "ORDER BY 1 ASC"
        }

        let selectList = table.columns.isEmpty ? "*" : table.columns.map {
            "\"\($0.name)\"::text AS \"\($0.name)\""
        }.joined(separator: ", ")

        let sql = """
            SELECT \(selectList) FROM \(table.qualifiedName)
            \(whereClause)
            \(orderClause)
            LIMIT \(limit) OFFSET \(offset)
            """.trimmingCharacters(in: .whitespacesAndNewlines)

        let countSQL = """
            SELECT count(*) FROM \(table.qualifiedName)
            \(whereClause)
            """.trimmingCharacters(in: .whitespacesAndNewlines)

        return (sql, countSQL)
    }

    // MARK: - Condition Builders

    private func buildCondition(_ filter: FilterConstraint) -> String? {
        let col = "\"\(filter.columnName)\""

        switch filter.operation {
        case .equals:
            switch filter.value {
            case .text(let v): return "\(col) = \(escapeString(v))"
            case .number(let v): return "\(col) = \(v)"
            case .boolean(let v): return "\(col) = \(v)"
            default: return nil
            }
        case .notEquals:
            switch filter.value {
            case .text(let v): return "\(col) != \(escapeString(v))"
            case .number(let v): return "\(col) != \(v)"
            default: return nil
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
            if case .number(let v) = filter.value { return "\(col) >= \(v)" }
            return nil
        case .lessOrEqual:
            if case .number(let v) = filter.value { return "\(col) <= \(v)" }
            return nil
        case .between:
            switch filter.value {
            case .range(let lo, let hi): return "\(col) BETWEEN \(lo) AND \(hi)"
            case .dateRange(let from, let to):
                return "\(col) BETWEEN \(escapeString(from.ISO8601Format())) AND \(escapeString(to.ISO8601Format()))"
            default: return nil
            }
        case .isNull:
            return "\(col) IS NULL"
        case .isNotNull:
            return "\(col) IS NOT NULL"
        case .inList:
            if case .list(let items) = filter.value {
                return "\(col) IN (\(items.map { escapeString($0) }.joined(separator: ", ")))"
            }
            return nil
        }
    }

    private func buildGlobalSearch(_ searchText: String, columns: [ColumnInfo]) -> String {
        let pattern = escapeString("%\(escapeLike(searchText))%")
        return columns.compactMap { col -> String? in
            if col.isTextSearchable { return "\"\(col.name)\" ILIKE \(pattern)" }
            if col.isNumeric { return "\"\(col.name)\"::text ILIKE \(pattern)" }
            return nil
        }.joined(separator: " OR ")
    }

    // MARK: - SQL Safety

    private func escapeString(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
