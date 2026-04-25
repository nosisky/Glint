import SwiftUI

@MainActor
@Observable
final class AppState {
    // Connection
    var savedConnections: [ConnectionConfig] = []
    var activeConnectionId: UUID?
    var connectionPool: ConnectionPool?

    var isConnecting = false
    var connectionError: String?
    var showConnectionSheet = false

    // Database
    var databases: [String] = []
    var currentDatabase: String = ""

    // Schema
    var schemas: [DatabaseSchemaInfo] = []
    var selectedSchema: String = "public"
    var selectedTable: TableInfo?
    var isLoadingSchema = false

    // Data Grid
    var queryResult: QueryResult = .empty
    var isLoadingData = false
    var currentPage = 1
    var pageSize = 200

    // Filters
    var filters: [FilterConstraint] = []
    var globalSearchText = ""
    var orderByColumn: String?
    var orderAscending = true

    // Editing
    var pendingEdits: [PendingEdit] = []
    var editingCellId: String?

    // UI
    var statusMessage = "Ready"
    var selectedSidebarItem: SidebarItem?
    var showConsole = false
    var showFilterBar = false

    // MARK: - Computed

    var isConnected: Bool { connectionPool != nil }
    var activeConfig: ConnectionConfig? { savedConnections.first { $0.id == activeConnectionId } }
    var hasActiveFilters: Bool { !filters.isEmpty || !globalSearchText.isEmpty }
    var hasPendingEdits: Bool { !pendingEdits.isEmpty }

    // MARK: - Persistence

    private static let savedConnectionsKey = "glint.savedConnections"

    func loadSavedConnections() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedConnectionsKey),
              let configs = try? JSONDecoder().decode([ConnectionConfig].self, from: data)
        else { return }
        savedConnections = configs
    }

    func persistConnections() {
        guard let data = try? JSONEncoder().encode(savedConnections) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedConnectionsKey)
    }

    func addConnection(_ config: ConnectionConfig) {
        savedConnections.append(config)
        persistConnections()
    }

    func removeConnection(_ config: ConnectionConfig) {
        savedConnections.removeAll { $0.id == config.id }
        try? KeychainService.deletePassword(account: config.keychainAccount)
        persistConnections()
    }

    // MARK: - Connection Lifecycle

    func connect(config: ConnectionConfig, password: String) async {
        isConnecting = true
        connectionError = nil
        statusMessage = "Connecting to \(config.host)…"

        do {
            try KeychainService.savePassword(password, account: config.keychainAccount)
            let pool = ConnectionPool(config: config, password: password)
            try await pool.connect()
            connectionPool = pool
            activeConnectionId = config.id
            currentDatabase = config.database
            statusMessage = "Connected to \(config.database)"
            await loadDatabases()
            await loadSchema()
        } catch {
            connectionError = error.localizedDescription
            statusMessage = "Connection failed"
        }

        isConnecting = false
    }

    func disconnect() async {
        if let pool = connectionPool { await pool.disconnectAll() }
        connectionPool = nil
        activeConnectionId = nil
        databases = []
        currentDatabase = ""
        schemas = []
        selectedTable = nil
        queryResult = .empty
        filters = []
        globalSearchText = ""
        statusMessage = "Disconnected"
    }

    // MARK: - Database Listing

    func loadDatabases() async {
        guard let pool = connectionPool else { return }
        do {
            let conn = try await pool.getConnection()
            let introspector = SchemaIntrospector(connection: conn)
            databases = try await introspector.fetchDatabases()
        } catch {
            databases = [currentDatabase]
        }
    }

    func switchDatabase(_ dbName: String) async {
        guard dbName != currentDatabase,
              let config = activeConfig,
              let password = try? KeychainService.readPassword(account: config.keychainAccount)
        else { return }

        if let pool = connectionPool { await pool.disconnectAll() }
        connectionPool = nil
        schemas = []
        selectedTable = nil
        queryResult = .empty
        currentDatabase = dbName
        statusMessage = "Switching to \(dbName)…"

        var newConfig = config
        newConfig.database = dbName

        do {
            let pool = ConnectionPool(config: newConfig, password: password)
            try await pool.connect()
            connectionPool = pool
            statusMessage = "Connected to \(dbName)"
            await loadSchema()
        } catch {
            statusMessage = "Failed to switch: \(error.localizedDescription)"
        }
    }

    // MARK: - Schema Loading

    func loadSchema() async {
        guard let pool = connectionPool else { return }
        isLoadingSchema = true
        statusMessage = "Loading schema…"

        do {
            let conn = try await pool.getConnection()
            let introspector = SchemaIntrospector(connection: conn)
            let schemaInfos = try await introspector.fetchSchemas()

            var loadedSchemas: [DatabaseSchemaInfo] = []
            for schema in schemaInfos {
                let fullSchema = try await introspector.fetchFullSchema(schema: schema.name)
                loadedSchemas.append(fullSchema)
            }
            schemas = loadedSchemas

            if schemas.isEmpty {
                schemas = [try await introspector.fetchFullSchema(schema: "public")]
            }

            let tableCount = schemas.flatMap(\.tables).count
            statusMessage = "Schema loaded — \(tableCount) table\(tableCount == 1 ? "" : "s")"
        } catch {
            statusMessage = "Schema load failed: \(error.localizedDescription)"
        }

        isLoadingSchema = false
    }

    // MARK: - Data Fetching

    func fetchTableData() async {
        guard let pool = connectionPool, let table = selectedTable else { return }
        isLoadingData = true

        do {
            let conn = try await pool.getConnection()
            let fetcher = DataFetcher(connection: conn)
            queryResult = try await fetcher.fetch(
                table: table,
                filters: filters,
                globalSearch: globalSearchText.isEmpty ? nil : globalSearchText,
                orderBy: orderByColumn,
                ascending: orderAscending,
                pageSize: pageSize,
                offset: (currentPage - 1) * pageSize
            )
            statusMessage = "\(queryResult.totalCount) rows · \(String(format: "%.1f", queryResult.executionTimeMs))ms"
        } catch {
            statusMessage = "Query failed: \(error.localizedDescription)"
        }

        isLoadingData = false
    }

    func selectTable(_ table: TableInfo) async {
        selectedTable = table
        currentPage = 1
        filters = []
        globalSearchText = ""
        orderByColumn = nil
        orderAscending = true
        pendingEdits = []
        await fetchTableData()
    }

    // MARK: - Filtering

    func addFilter(_ filter: FilterConstraint) async {
        filters.append(filter)
        currentPage = 1
        await fetchTableData()
    }

    func removeFilter(_ id: UUID) async {
        filters.removeAll { $0.id == id }
        currentPage = 1
        await fetchTableData()
    }

    func clearAllFilters() async {
        filters.removeAll()
        globalSearchText = ""
        currentPage = 1
        await fetchTableData()
    }

    func performGlobalSearch(_ text: String) async {
        globalSearchText = text
        currentPage = 1
        await fetchTableData()
    }

    // MARK: - Pagination

    func nextPage() async {
        guard queryResult.hasMore else { return }
        currentPage += 1
        await fetchTableData()
    }

    func previousPage() async {
        guard currentPage > 1 else { return }
        currentPage -= 1
        await fetchTableData()
    }

    func goToPage(_ page: Int) async {
        currentPage = max(1, min(page, queryResult.totalPages))
        await fetchTableData()
    }

    // MARK: - Sorting

    func toggleSort(column: String) async {
        if orderByColumn == column {
            orderAscending.toggle()
        } else {
            orderByColumn = column
            orderAscending = true
        }
        currentPage = 1
        await fetchTableData()
    }

    // MARK: - Editing

    func commitEdits() async {
        guard let pool = connectionPool, let table = selectedTable, !pendingEdits.isEmpty else { return }

        let editsByRow = Dictionary(grouping: pendingEdits) { $0.rowId }

        do {
            let conn = try await pool.getConnection()

            for (rowId, edits) in editsByRow {
                guard let originalRow = queryResult.rows.first(where: { $0.id == rowId }),
                      let pkColumn = table.columns.first(where: { $0.isPrimaryKey }),
                      let pkIndex = table.columns.firstIndex(where: { $0.isPrimaryKey }),
                      let pkValue = originalRow[pkIndex]
                else { continue }

                let setClauses = edits.compactMap { edit -> String? in
                    guard edit.hasChanged else { return nil }
                    let qCol = SQLSanitizer.quoteIdentifier(edit.columnName)
                    if let newValue = edit.newValue {
                        return "\(qCol) = \(SQLSanitizer.quoteLiteral(newValue))"
                    }
                    return "\(qCol) = NULL"
                }

                guard !setClauses.isEmpty else { continue }

                let qTable = "\(SQLSanitizer.quoteIdentifier(table.schema)).\(SQLSanitizer.quoteIdentifier(table.name))"
                let qPK = SQLSanitizer.quoteIdentifier(pkColumn.name)
                let pkLiteral = SQLSanitizer.quoteLiteral(pkValue.rawValue ?? "")
                let sql = "UPDATE \(qTable) SET \(setClauses.joined(separator: ", ")) WHERE \(qPK) = \(pkLiteral)"

                let rows = try await conn.query(sql)
                for try await _ in rows {}
            }

            pendingEdits.removeAll()
            statusMessage = "Changes committed"
            await fetchTableData()
        } catch {
            statusMessage = "Commit failed: \(error.localizedDescription)"
        }
    }

    func discardEdits() {
        pendingEdits.removeAll()
        statusMessage = "Changes discarded"
    }

    func insertNewRow() {
        guard let table = selectedTable else { return }
        let newRow = TableRow(values: table.columns.map {
            CellValue(columnName: $0.name, rawValue: nil, dataType: $0.udtName)
        })
        queryResult = QueryResult(
            rows: [newRow] + queryResult.rows,
            columns: queryResult.columns,
            totalCount: queryResult.totalCount + 1,
            pageSize: queryResult.pageSize,
            currentOffset: queryResult.currentOffset,
            executionTimeMs: queryResult.executionTimeMs,
            query: queryResult.query
        )
        statusMessage = "New row — edit values and save"
    }

    // MARK: - Schema Refresh

    func loadColumnsForTable(_ table: TableInfo) async -> TableInfo? {
        guard let pool = connectionPool else { return nil }
        do {
            let conn = try await pool.getConnection()
            let introspector = SchemaIntrospector(connection: conn)
            var result = table
            var columns = try await introspector.fetchColumns(schema: table.schema, table: table.name)
            let enums = try await introspector.fetchEnumTypes()
            let fks = try await introspector.fetchForeignKeys(schema: table.schema)

            for i in columns.indices where columns[i].dataType.lowercased() == "user-defined" {
                columns[i].enumValues = enums[columns[i].udtName]
            }
            for fk in fks where fk.tableName == table.name {
                if let i = columns.firstIndex(where: { $0.name == fk.columnName }) {
                    columns[i].foreignKey = ForeignKeyRef(
                        constraintName: fk.constraintName,
                        referencedTable: fk.referencedTable,
                        referencedColumn: fk.referencedColumn
                    )
                }
            }

            result.columns = columns
            return result
        } catch {
            return nil
        }
    }
}

// MARK: - Sidebar Item

enum SidebarItem: Hashable {
    case connection(UUID)
    case schema(String)
    case table(TableInfo)
}
