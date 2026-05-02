import Testing
@testable import Glint

// MARK: - quoteIdentifier

@Test func quoteIdentifierWrapsInDoubleQuotes() {
    #expect(SQLSanitizer.quoteIdentifier("users") == "\"users\"")
}

@Test func quoteIdentifierEscapesEmbeddedDoubleQuotes() {
    #expect(SQLSanitizer.quoteIdentifier("table\"name") == "\"table\"\"name\"")
}

@Test func quoteIdentifierHandlesEmptyString() {
    #expect(SQLSanitizer.quoteIdentifier("") == "\"\"")
}

@Test func quoteIdentifierPreservesSpecialChars() {
    #expect(SQLSanitizer.quoteIdentifier("my table") == "\"my table\"")
    #expect(SQLSanitizer.quoteIdentifier("column-name") == "\"column-name\"")
}

// MARK: - quoteLiteral

@Test func quoteLiteralWrapsInSingleQuotes() {
    #expect(SQLSanitizer.quoteLiteral("hello") == "'hello'")
}

@Test func quoteLiteralEscapesSingleQuotes() {
    #expect(SQLSanitizer.quoteLiteral("O'Brien") == "'O''Brien'")
}

@Test func quoteLiteralDoublesSingleQuotes() {
    #expect(SQLSanitizer.quoteLiteral("it's a 'test'") == "'it''s a ''test'''")
}

@Test func quoteLiteralStripsNullBytes() {
    #expect(SQLSanitizer.quoteLiteral("ab\0cd") == "'abcd'")
}

@Test func quoteLiteralHandlesEmptyString() {
    #expect(SQLSanitizer.quoteLiteral("") == "''")
}

@Test func quoteLiteralPreservesBackslashes() {
    #expect(SQLSanitizer.quoteLiteral("path\\to\\file") == "'path\\to\\file'")
}

@Test func quoteLiteralDoesNotUseEStringPrefix() {
    let result = SQLSanitizer.quoteLiteral("test")
    #expect(!result.hasPrefix("E'"), "quoteLiteral must not use E-string syntax")
}

// MARK: - escapeLike

@Test func escapeLikeEscapesPercent() {
    #expect(SQLSanitizer.escapeLike("100%") == "100\\%")
}

@Test func escapeLikeEscapesUnderscore() {
    #expect(SQLSanitizer.escapeLike("user_name") == "user\\_name")
}

@Test func escapeLikeEscapesBackslash() {
    #expect(SQLSanitizer.escapeLike("path\\dir") == "path\\\\dir")
}

@Test func escapeLikeHandlesAllMetacharacters() {
    #expect(SQLSanitizer.escapeLike("10%_\\x") == "10\\%\\_\\\\x")
}

// MARK: - Destructive Detection

@Test func isDestructiveDetectsDropStatements() {
    #expect(SQLSanitizer.isDestructive("DROP TABLE users"))
    #expect(SQLSanitizer.isDestructive("drop schema public cascade"))
    #expect(SQLSanitizer.isDestructive("  DROP INDEX idx_name"))
}

@Test func isDestructiveDetectsDeleteStatements() {
    #expect(SQLSanitizer.isDestructive("DELETE FROM users WHERE id = 1"))
    #expect(SQLSanitizer.isDestructive("delete from orders"))
}

@Test func isDestructiveDetectsUpdateStatements() {
    #expect(SQLSanitizer.isDestructive("UPDATE users SET name = 'test'"))
}

@Test func isDestructiveDetectsTruncate() {
    #expect(SQLSanitizer.isDestructive("TRUNCATE TABLE users"))
}

@Test func isDestructiveDetectsAlter() {
    #expect(SQLSanitizer.isDestructive("ALTER TABLE users ADD COLUMN age int"))
}

@Test func isDestructiveReturnsFalseForSelect() {
    #expect(!SQLSanitizer.isDestructive("SELECT * FROM users"))
    #expect(!SQLSanitizer.isDestructive("WITH cte AS (SELECT 1) SELECT * FROM cte"))
}

@Test func isDestructiveReturnsFalseForInsert() {
    #expect(!SQLSanitizer.isDestructive("INSERT INTO users (name) VALUES ('test')"))
}

// MARK: - WHERE Clause Detection

@Test func lacksWhereClauseDetectsDeleteWithoutWhere() {
    #expect(SQLSanitizer.lacksWhereClause("DELETE FROM users"))
    #expect(!SQLSanitizer.lacksWhereClause("DELETE FROM users WHERE id = 1"))
}

@Test func lacksWhereClauseDetectsUpdateWithoutWhere() {
    #expect(SQLSanitizer.lacksWhereClause("UPDATE users SET name = 'x'"))
    #expect(!SQLSanitizer.lacksWhereClause("UPDATE users SET name = 'x' WHERE id = 1"))
}

@Test func lacksWhereClauseReturnsFalseForOtherStatements() {
    #expect(!SQLSanitizer.lacksWhereClause("SELECT * FROM users"))
    #expect(!SQLSanitizer.lacksWhereClause("DROP TABLE users"))
}

// MARK: - Injection Vectors

@Test func quoteLiteralPreventsBasicInjection() {
    let malicious = "'; DROP TABLE users; --"
    let result = SQLSanitizer.quoteLiteral(malicious)
    #expect(result == "'''; DROP TABLE users; --'")
}

@Test func quoteIdentifierPreventsInjectionViaColumnName() {
    let malicious = "col\"; DROP TABLE users; --"
    let result = SQLSanitizer.quoteIdentifier(malicious)
    #expect(result == "\"col\"\"; DROP TABLE users; --\"")
}
