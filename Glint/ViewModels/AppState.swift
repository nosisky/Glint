import SwiftUI

/// Root application state. @Observable for automatic SwiftUI reactivity.
@MainActor
@Observable
final class AppState {
    // Connection management
    var savedConnections: [ConnectionConfig] = []
    var activeConnectionId: UUID?
    var connectionPool: ConnectionPool?
    var activePassword: String?
    var isConnecting = false
    var connectionError: String?
    var showConnectionSheet = false

    // Database state
    var databases: [String] = []
    var currentDatabase: String = ""

    // Schema state
    var schemas: [DatabaseSchemaInfo] = []
    var selectedSchema: String = "public"
    var selectedTable: TableInfo?
    var isLoadingSchema = false

    // Data grid state
    var queryResult: QueryResult = .empty
    var isLoadingData = false
    var currentPage = 1
    var pageSize = 200

    // Filter state
    var filters: [FilterConstraint] = []
    var globalSearchText = ""
    var orderByColumn: String?
    var orderAscending = true

    // Inline editing
    var pendingEdits: [PendingEdit] = []
    var editingCellId: String?

    // UI state
    var statusMessage = "Ready"
    var selectedSidebarItem: SidebarItem?
    var showConsole = false
    var showFilterBar = false

    // MARK: - Computed

    var isConnected: Bool { connectionPool != nil }

    var activeConfig: ConnectionConfig? {
        savedConnections.first { $0.id == activeConnectionId }
    }

    var hasActiveFilters: Bool {
        !filters.isEmpty || !globalSearchText.isEmpty
    }

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
            activePassword = password
            currentDatabase = config.database
            statusMessage = "Connected to \(config.database)"

            // Load available databases and schema
            await loadDatabases()
            await loadSchema()
        } catch {
            connectionError = error.localizedDescription
            statusMessage = "Connection failed"
        }

        isConnecting = false
    }

    func disconnect() async {
        if let pool = connectionPool {
            await pool.disconnectAll()
        }
        connectionPool = nil
        activeConnectionId = nil
        activePassword = nil
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
            // Non-fatal — just won't show the database picker
            databases = [currentDatabase]
        }
    }

    func switchDatabase(_ dbName: String) async {
        guard dbName != currentDatabase,
              let config = activeConfig,
              let password = activePassword
        else { return }

        // Disconnect from current database
        if let pool = connectionPool {
            await pool.disconnectAll()
        }
        connectionPool = nil
        schemas = []
        selectedTable = nil
        queryResult = .empty
        currentDatabase = dbName

        // Reconnect with the new database name
        var newConfig = config
        newConfig.database = dbName
        statusMessage = "Switching to \(dbName)…"

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
            for var schema in schemaInfos {
                let tables = try await introspector.fetchTables(schema: schema.name)
                // Load columns for each table so they're ready for selectTable
                var tablesWithColumns: [TableInfo] = []
                for var table in tables {
                    table.columns = try await introspector.fetchColumns(
                        schema: schema.name,
                        table: table.name
                    )
                    tablesWithColumns.append(table)
                }
                schema.tables = tablesWithColumns
                loadedSchemas.append(schema)
            }
            schemas = loadedSchemas

            if schemas.isEmpty {
                let publicSchema = try await introspector.fetchFullSchema(schema: "public")
                schemas = [publicSchema]
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
        let offset = (currentPage - 1) * pageSize

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
                offset: offset
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

    // MARK: - Inline Editing

    func commitEdits() async {
        guard let pool = connectionPool, let table = selectedTable else { return }
        guard !pendingEdits.isEmpty else { return }

        // Group edits by row
        let editsByRow = Dictionary(grouping: pendingEdits) { $0.rowId }

        do {
            let conn = try await pool.getConnection()

            for (rowId, edits) in editsByRow {
                // Find the original row to get PK value for the WHERE clause
                guard let originalRow = queryResult.rows.first(where: { $0.id == rowId }),
                      let pkColumn = table.columns.first(where: { $0.isPrimaryKey }),
                      let pkIndex = table.columns.firstIndex(where: { $0.isPrimaryKey }),
                      let pkValue = originalRow[pkIndex]
                else { continue }

                // Build SET clause
                let setClauses = edits.compactMap { edit -> String? in
                    guard edit.hasChanged else { return nil }
                    if let newValue = edit.newValue {
                        let escaped = newValue.replacingOccurrences(of: "'", with: "''")
                        return "\"\(edit.columnName)\" = '\(escaped)'"
                    } else {
                        return "\"\(edit.columnName)\" = NULL"
                    }
                }

                guard !setClauses.isEmpty else { continue }

                let pkEscaped = (pkValue.rawValue ?? "").replacingOccurrences(of: "'", with: "''")
                let sql = """
                    UPDATE \(table.qualifiedName)
                    SET \(setClauses.joined(separator: ", "))
                    WHERE "\(pkColumn.name)" = '\(pkEscaped)'
                    """

                let rows = try await conn.query(sql)
                for try await _ in rows { } // drain
            }

            pendingEdits.removeAll()
            statusMessage = "Changes committed"

            // Refresh data to show committed values
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
        let newRow = TableRow(values: table.columns.map { col in
            CellValue(columnName: col.name, rawValue: nil, dataType: col.udtName)
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
            var updatedTable = table
            var columns = try await introspector.fetchColumns(
                schema: table.schema,
                table: table.name
            )

            // Enrich with enums and FK references
            let enums = try await introspector.fetchEnumTypes()
            let foreignKeys = try await introspector.fetchForeignKeys(schema: table.schema)

            for j in columns.indices {
                if columns[j].dataType.lowercased() == "user-defined" {
                    columns[j].enumValues = enums[columns[j].udtName]
                }
            }
            for fk in foreignKeys where fk.tableName == table.name {
                if let j = columns.firstIndex(where: { $0.name == fk.columnName }) {
                    columns[j].foreignKey = ForeignKeyRef(
                        constraintName: fk.constraintName,
                        referencedTable: fk.referencedTable,
                        referencedColumn: fk.referencedColumn
                    )
                }
            }

            updatedTable.columns = columns
            return updatedTable
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
