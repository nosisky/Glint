import Testing
@testable import Glint

// MARK: - Basic Query Generation

@Test func buildQueryProducesSelectWithLimit() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let (sql, _) = builder.buildQuery(table: table, filters: [], globalSearch: nil)

    #expect(sql.contains("FROM \"public\".\"users\""))
    #expect(sql.contains("LIMIT 200 OFFSET 0"))
}

@Test func buildQueryUsesProvidedLimitAndOffset() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let (sql, _) = builder.buildQuery(table: table, filters: [], globalSearch: nil, limit: 50, offset: 100)

    #expect(sql.contains("LIMIT 50 OFFSET 100"))
}

@Test func buildQueryQuotesSchemaAndTableNames() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "my schema", name: "my table")
    let (sql, countSQL) = builder.buildQuery(table: table, filters: [], globalSearch: nil)

    #expect(sql.contains("\"my schema\".\"my table\""))
    #expect(countSQL.contains("\"my schema\".\"my table\""))
}

@Test func buildQueryGeneratesCountSQL() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let (_, countSQL) = builder.buildQuery(table: table, filters: [], globalSearch: nil)

    #expect(countSQL.hasPrefix("SELECT count(*)"))
    #expect(countSQL.contains("FROM \"public\".\"users\""))
    #expect(!countSQL.contains("LIMIT"))
}

// MARK: - Ordering

@Test func buildQueryOrdersByPrimaryKey() {
    let builder = QueryBuilder()
    let pk = ColumnInfo(
        name: "id", tableName: "users", dataType: "integer", udtName: "int4",
        isNullable: false, isPrimaryKey: true, hasDefault: true,
        defaultValue: nil, characterMaxLength: nil, numericPrecision: nil, ordinalPosition: 0
    )
    let table = TableInfo(schema: "public", name: "users", columns: [pk])
    let (sql, _) = builder.buildQuery(table: table, filters: [], globalSearch: nil)

    #expect(sql.contains("ORDER BY \"id\" ASC"))
}

@Test func buildQueryOrdersBySpecifiedColumn() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let (sql, _) = builder.buildQuery(
        table: table, filters: [], globalSearch: nil,
        orderBy: "created_at", ascending: false
    )

    #expect(sql.contains("ORDER BY \"created_at\" DESC NULLS LAST"))
}

@Test func buildQueryFallsBackToOrderByFirstColumn() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let (sql, _) = builder.buildQuery(table: table, filters: [], globalSearch: nil)

    #expect(sql.contains("ORDER BY 1 ASC"))
}

// MARK: - Filters

@Test func buildQueryWithEqualsFilter() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let filter = FilterConstraint(
        columnName: "name", columnType: "text",
        operation: .equals, value: .text("Alice")
    )
    let (sql, _) = builder.buildQuery(table: table, filters: [filter], globalSearch: nil)

    #expect(sql.contains("WHERE \"name\" = 'Alice'"))
}

@Test func buildQueryWithContainsFilter() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let filter = FilterConstraint(
        columnName: "email", columnType: "text",
        operation: .contains, value: .text("@example")
    )
    let (sql, _) = builder.buildQuery(table: table, filters: [filter], globalSearch: nil)

    #expect(sql.contains("\"email\"::text ILIKE '%@example%'"))
}

@Test func buildQueryWithIsNullFilter() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let filter = FilterConstraint(
        columnName: "deleted_at", columnType: "timestamp",
        operation: .isNull, value: .none
    )
    let (sql, _) = builder.buildQuery(table: table, filters: [filter], globalSearch: nil)

    #expect(sql.contains("WHERE \"deleted_at\" IS NULL"))
}

@Test func buildQueryWithMultipleFilters() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let filters = [
        FilterConstraint(columnName: "age", columnType: "int4", operation: .greaterThan, value: .number(18)),
        FilterConstraint(columnName: "active", columnType: "bool", operation: .equals, value: .boolean(true)),
    ]
    let (sql, _) = builder.buildQuery(table: table, filters: filters, globalSearch: nil)

    #expect(sql.contains("\"age\" > 18.0"))
    #expect(sql.contains("\"active\" = true"))
    #expect(sql.contains(" AND "))
}

@Test func buildQueryWithBetweenFilter() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "orders")
    let filter = FilterConstraint(
        columnName: "amount", columnType: "numeric",
        operation: .between, value: .range(low: 10.0, high: 100.0)
    )
    let (sql, _) = builder.buildQuery(table: table, filters: [filter], globalSearch: nil)

    #expect(sql.contains("\"amount\" BETWEEN 10.0 AND 100.0"))
}

// MARK: - Filter Escaping

@Test func filterValueWithSingleQuoteIsEscaped() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let filter = FilterConstraint(
        columnName: "name", columnType: "text",
        operation: .equals, value: .text("O'Brien")
    )
    let (sql, _) = builder.buildQuery(table: table, filters: [filter], globalSearch: nil)

    #expect(sql.contains("'O''Brien'"))
}

@Test func containsFilterEscapesLikeMetacharacters() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "logs")
    let filter = FilterConstraint(
        columnName: "message", columnType: "text",
        operation: .contains, value: .text("100%")
    )
    let (sql, _) = builder.buildQuery(table: table, filters: [filter], globalSearch: nil)

    #expect(sql.contains("100\\%"))
}

// MARK: - Select List

@Test func buildQuerySelectsColumnsWithTextCastAndXmin() {
    let builder = QueryBuilder()
    let col = ColumnInfo(
        name: "id", tableName: "users", dataType: "integer", udtName: "int4",
        isNullable: false, isPrimaryKey: true, hasDefault: true,
        defaultValue: nil, characterMaxLength: nil, numericPrecision: nil, ordinalPosition: 0
    )
    let table = TableInfo(schema: "public", name: "users", columns: [col])
    let (sql, _) = builder.buildQuery(table: table, filters: [], globalSearch: nil)

    // Ensure it casts columns to text for server-side formatting
    #expect(sql.contains("::text AS"), "SELECT list should cast columns to text")
    // Ensure it fetches xmin for OCC
    #expect(sql.contains("xmin::text AS xmin"), "SELECT list should append xmin for concurrency control")
}

@Test func buildQueryUsesStarWhenNoColumnsKnown() {
    let builder = QueryBuilder()
    let table = TableInfo(schema: "public", name: "users")
    let (sql, _) = builder.buildQuery(table: table, filters: [], globalSearch: nil)

    #expect(sql.contains("SELECT * FROM"))
}
