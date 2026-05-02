//
//  QueryBuilder.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation

struct QueryBuilder: Sendable {

    func buildQuery(
        table: TableInfo,
        filters: [FilterConstraint],
        globalSearch: String?,
        orderBy: String? = nil,
        ascending: Bool = true,
        limit: Int? = 200,
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

        let qualifiedTable = "\(SQLSanitizer.quoteIdentifier(table.schema)).\(SQLSanitizer.quoteIdentifier(table.name))"

        let orderClause: String
        if let orderBy {
            let dir = ascending ? "ASC" : "DESC"
            orderClause = "ORDER BY \(qualifiedTable).\(SQLSanitizer.quoteIdentifier(orderBy)) \(dir) NULLS LAST"
        } else if let pk = table.columns.first(where: { $0.isPrimaryKey }) {
            orderClause = "ORDER BY \(qualifiedTable).\(SQLSanitizer.quoteIdentifier(pk.name)) ASC"
        } else {
            orderClause = "ORDER BY 1 ASC"
        }

        // PERF-02 Fix: Use ::text to format all complex types (dates, enums, geometries) perfectly
        // on the server. To preserve native index sorting, the ORDER BY clause uses the fully
        // qualified table column (e.g. table.col) instead of the SELECT alias.
        let selectList = table.columns.isEmpty ? "*" : table.columns.map {
            "\(qualifiedTable).\(SQLSanitizer.quoteIdentifier($0.name))::text AS \(SQLSanitizer.quoteIdentifier($0.name))"
        }.joined(separator: ", ")

        let paginationClause = limit != nil ? "\nLIMIT \(limit!) OFFSET \(offset)" : ""

        let sql = """
            SELECT \(selectList) FROM \(qualifiedTable)
            \(whereClause)
            \(orderClause)\(paginationClause)
            """.trimmingCharacters(in: .whitespacesAndNewlines)

        let countSQL = """
            SELECT count(*) FROM \(qualifiedTable)
            \(whereClause)
            """.trimmingCharacters(in: .whitespacesAndNewlines)

        return (sql, countSQL)
    }

    // MARK: - Condition Builders

    private func buildCondition(_ filter: FilterConstraint) -> String? {
        let col = SQLSanitizer.quoteIdentifier(filter.columnName)

        switch filter.operation {
        case .equals:
            switch filter.value {
            case .text(let v): return "\(col) = \(SQLSanitizer.quoteLiteral(v))"
            case .number(let v): return "\(col) = \(v)"
            case .boolean(let v): return "\(col) = \(v)"
            default: return nil
            }
        case .notEquals:
            switch filter.value {
            case .text(let v): return "\(col) != \(SQLSanitizer.quoteLiteral(v))"
            case .number(let v): return "\(col) != \(v)"
            default: return nil
            }
        case .contains:
            if case .text(let v) = filter.value {
                return "\(col)::text ILIKE \(SQLSanitizer.quoteLiteral("%\(SQLSanitizer.escapeLike(v))%"))"
            }
            return nil
        case .startsWith:
            if case .text(let v) = filter.value {
                return "\(col)::text ILIKE \(SQLSanitizer.quoteLiteral("\(SQLSanitizer.escapeLike(v))%"))"
            }
            return nil
        case .endsWith:
            if case .text(let v) = filter.value {
                return "\(col)::text ILIKE \(SQLSanitizer.quoteLiteral("%\(SQLSanitizer.escapeLike(v))"))"
            }
            return nil
        case .greaterThan:
            switch filter.value {
            case .number(let v): return "\(col) > \(v)"
            case .date(let d): return "\(col) > \(SQLSanitizer.quoteLiteral(d.ISO8601Format()))"
            default: return nil
            }
        case .lessThan:
            switch filter.value {
            case .number(let v): return "\(col) < \(v)"
            case .date(let d): return "\(col) < \(SQLSanitizer.quoteLiteral(d.ISO8601Format()))"
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
                return "\(col) BETWEEN \(SQLSanitizer.quoteLiteral(from.ISO8601Format())) AND \(SQLSanitizer.quoteLiteral(to.ISO8601Format()))"
            default: return nil
            }
        case .isNull:
            return "\(col) IS NULL"
        case .isNotNull:
            return "\(col) IS NOT NULL"
        case .inList:
            if case .list(let items) = filter.value {
                return "\(col) IN (\(items.map { SQLSanitizer.quoteLiteral($0) }.joined(separator: ", ")))"
            }
            return nil
        }
    }

    private func buildGlobalSearch(_ searchText: String, columns: [ColumnInfo]) -> String {
        let pattern = SQLSanitizer.quoteLiteral("%\(SQLSanitizer.escapeLike(searchText))%")
        return columns.compactMap { col -> String? in
            let quoted = SQLSanitizer.quoteIdentifier(col.name)
            if col.isTextSearchable { return "\(quoted) ILIKE \(pattern)" }
            if col.isNumeric { return "\(quoted)::text ILIKE \(pattern)" }
            return nil
        }.joined(separator: " OR ")
    }
}
