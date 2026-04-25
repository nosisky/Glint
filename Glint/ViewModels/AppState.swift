import SwiftUI

/// Root application state. @Observable for automatic SwiftUI reactivity.
@MainActor
@Observable
final class AppState {
    // Connection management
    var savedConnections: [ConnectionConfig] = []
    var activeConnectionId: UUID?
    var connectionPool: ConnectionPool?
    var isConnecting = false
    var connectionError: String?
    var showConnectionSheet = false

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
            statusMessage = "Connected to \(config.database)"
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
        schemas = []
        selectedTable = nil
        queryResult = .empty
        filters = []
        globalSearchText = ""
        statusMessage = "Disconnected"
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
                schema.tables = try await introspector.fetchTables(schema: schema.name)
                loadedSchemas.append(schema)
            }
            schemas = loadedSchemas

            if schemas.isEmpty {
                let publicSchema = try await introspector.fetchFullSchema(schema: "public")
                schemas = [publicSchema]
            }

            statusMessage = "Schema loaded — \(schemas.flatMap(\.tables).count) tables"
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

    // MARK: - Schema Refresh

    func loadColumnsForTable(_ table: TableInfo) async -> TableInfo? {
        guard let pool = connectionPool else { return nil }
        do {
            let conn = try await pool.getConnection()
            let introspector = SchemaIntrospector(connection: conn)
            var updatedTable = table
            updatedTable.columns = try await introspector.fetchColumns(
                schema: table.schema,
                table: table.name
            )
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
