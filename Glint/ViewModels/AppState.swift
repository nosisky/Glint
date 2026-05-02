//
//  AppState.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI
import PostgresNIO

@MainActor
@Observable
final class AppState {
    // Connection
    var savedConnections: [ConnectionConfig] = []
    var activeConnectionId: UUID?
    
    var connectionPool: ConnectionPool? {
        get { workspaceTabs[activeTabIndex].connectionPool }
        set { workspaceTabs[activeTabIndex].connectionPool = newValue }
    }
    /// In-memory password for the active session — used by switchDatabase.
    /// Keychain is used for persistence across launches; this is the runtime fallback.
    private var activeSessionPassword: String?

    var isConnecting = false
    var connectionError: String?
    var showConnectionSheet = false
    /// When true, keeps isConnected == true during a database switch
    /// so the sidebar UI isn't destroyed mid-transition.
    private var isSwitchingDatabase = false

    var databases: [String] {
        get { workspaceTabs[activeTabIndex].databases }
        set { workspaceTabs[activeTabIndex].databases = newValue }
    }
    var currentDatabase: String {
        get { workspaceTabs[activeTabIndex].currentDatabase }
        set { workspaceTabs[activeTabIndex].currentDatabase = newValue }
    }

    // Schema
    var schemas: [DatabaseSchemaInfo] {
        get { workspaceTabs[activeTabIndex].schemas }
        set { workspaceTabs[activeTabIndex].schemas = newValue }
    }
    var selectedSchema: String {
        get { workspaceTabs[activeTabIndex].selectedSchema }
        set { workspaceTabs[activeTabIndex].selectedSchema = newValue }
    }
    var isLoadingSchema: Bool {
        get { workspaceTabs[activeTabIndex].isLoadingSchema }
        set { workspaceTabs[activeTabIndex].isLoadingSchema = newValue }
    }
    
    var pageSize: Int {
        let stored = UserDefaults.standard.integer(forKey: "glint.pageSize")
        return stored > 0 ? stored : 200
    }
    
    // MARK: - Workspace Tabs
    
    var workspaceTabs: [WorkspaceTab] = [WorkspaceTab()]
    var activeWorkspaceTabId: UUID? = nil
    
    func addNewTab() {
        var newTab = WorkspaceTab()
        // Instantly clone the current connection and schema state!
        // Because ConnectionPool is thread-safe, multiple tabs can multiplex queries
        // over the exact same pool if they are on the same database.
        newTab.connectionPool = self.connectionPool
        newTab.currentDatabase = self.currentDatabase
        newTab.databases = self.databases
        newTab.schemas = self.schemas
        newTab.selectedSchema = self.selectedSchema
        
        workspaceTabs.append(newTab)
        activeWorkspaceTabId = newTab.id
    }
    
    func closeTab(id: UUID) {
        if workspaceTabs.count <= 1 { return } // Keep at least one tab
        
        let idx = workspaceTabs.firstIndex(where: { $0.id == id }) ?? 0
        let poolToCheck = workspaceTabs[idx].connectionPool
        
        workspaceTabs.removeAll(where: { $0.id == id })
        
        // Garbage collect the connection pool if no other tab is using it
        if let poolToCheck {
            Task { await disconnectPoolIfNeeded(poolToCheck) }
        }
        
        // Select adjacent tab
        if activeWorkspaceTabId == id {
            let newIdx = min(idx, workspaceTabs.count - 1)
            activeWorkspaceTabId = workspaceTabs[newIdx].id
        }
    }
    
    private func disconnectPoolIfNeeded(_ pool: ConnectionPool?) async {
        guard let pool else { return }
        let isUsed = workspaceTabs.contains(where: { $0.connectionPool === pool })
        if !isUsed {
            await pool.disconnectAll()
        }
    }
    

    private var activeTabIndex: Int {
        guard let id = activeWorkspaceTabId,
              let idx = workspaceTabs.firstIndex(where: { $0.id == id }) else {
            return 0
        }
        return idx
    }

    var selectedTable: TableInfo? {
        get { workspaceTabs[activeTabIndex].selectedTable }
        set { workspaceTabs[activeTabIndex].selectedTable = newValue }
    }
    var selectedFunction: FunctionInfo? {
        get { workspaceTabs[activeTabIndex].selectedFunction }
        set { workspaceTabs[activeTabIndex].selectedFunction = newValue }
    }
    
    var queryResult: QueryResult {
        get { workspaceTabs[activeTabIndex].queryResult }
        set { workspaceTabs[activeTabIndex].queryResult = newValue }
    }
    var isLoadingData: Bool {
        get { workspaceTabs[activeTabIndex].isLoadingData }
        set { workspaceTabs[activeTabIndex].isLoadingData = newValue }
    }
    var currentPage: Int {
        get { workspaceTabs[activeTabIndex].currentPage }
        set { workspaceTabs[activeTabIndex].currentPage = newValue }
    }
    var filters: [FilterConstraint] {
        get { workspaceTabs[activeTabIndex].filters }
        set { workspaceTabs[activeTabIndex].filters = newValue }
    }
    var globalSearchText: String {
        get { workspaceTabs[activeTabIndex].globalSearchText }
        set { workspaceTabs[activeTabIndex].globalSearchText = newValue }
    }
    var orderByColumn: String? {
        get { workspaceTabs[activeTabIndex].orderByColumn }
        set { workspaceTabs[activeTabIndex].orderByColumn = newValue }
    }
    var orderAscending: Bool {
        get { workspaceTabs[activeTabIndex].orderAscending }
        set { workspaceTabs[activeTabIndex].orderAscending = newValue }
    }
    var pendingEdits: [PendingEdit] {
        get { workspaceTabs[activeTabIndex].pendingEdits }
        set { workspaceTabs[activeTabIndex].pendingEdits = newValue }
    }
    var editingCellId: String? {
        get { workspaceTabs[activeTabIndex].editingCellId }
        set { workspaceTabs[activeTabIndex].editingCellId = newValue }
    }
    var newRowIds: Set<UUID> {
        get { workspaceTabs[activeTabIndex].newRowIds }
        set { workspaceTabs[activeTabIndex].newRowIds = newValue }
    }
    var selectedRowIds: Set<UUID> {
        get { workspaceTabs[activeTabIndex].selectedRowIds }
        set { workspaceTabs[activeTabIndex].selectedRowIds = newValue }
    }

    // Query Editor (per-tab)
    var isQueryEditorOpen: Bool {
        get { workspaceTabs[activeTabIndex].isQueryEditorOpen }
        set { workspaceTabs[activeTabIndex].isQueryEditorOpen = newValue }
    }
    var customQueryText: String {
        get { workspaceTabs[activeTabIndex].customQueryText }
        set { workspaceTabs[activeTabIndex].customQueryText = newValue }
    }
    var customQueryResult: QueryResult? {
        get { workspaceTabs[activeTabIndex].customQueryResult }
        set { workspaceTabs[activeTabIndex].customQueryResult = newValue }
    }
    var queryExecutionError: String? {
        get { workspaceTabs[activeTabIndex].queryExecutionError }
        set { workspaceTabs[activeTabIndex].queryExecutionError = newValue }
    }
    var isExecutingQuery: Bool {
        get { workspaceTabs[activeTabIndex].isExecutingQuery }
        set { workspaceTabs[activeTabIndex].isExecutingQuery = newValue }
    }
    var queryWriteMode: Bool {
        get { workspaceTabs[activeTabIndex].queryWriteMode }
        set { workspaceTabs[activeTabIndex].queryWriteMode = newValue }
    }
    var queryHistory: [QueryHistoryEntry] {
        get { workspaceTabs[activeTabIndex].queryHistory }
        set { workspaceTabs[activeTabIndex].queryHistory = newValue }
    }

    // UI
    var statusMessage = "Ready"
    var selectedSidebarItem: SidebarItem?
    var showConsole = false
    var showFilterBar = false
    var isExporting = false
    var activeTab: ContentTab {
        get { workspaceTabs[activeTabIndex].activeTab }
        set { workspaceTabs[activeTabIndex].activeTab = newValue }
    }
    // Schema caches (cleared on disconnect / db switch)
    private var enumTypesCache: [String: [String]] = [:]
    private var foreignKeysBySchema: [String: [SchemaIntrospector.FKResult]] = [:]
    private var tableColumnsCache: [String: [ColumnInfo]] = [:]

    /// Active fetch task — cancelled when a new fetch starts to prevent stale data overwrites.
    private var activeFetchTask: Task<Void, Never>?

    // MARK: - Computed

    var isConnected: Bool { connectionPool != nil || isSwitchingDatabase }
    var activeConfig: ConnectionConfig? { savedConnections.first { $0.id == activeConnectionId } }
    var hasActiveFilters: Bool { !filters.isEmpty || !globalSearchText.isEmpty }
    var hasPendingEdits: Bool { !pendingEdits.isEmpty || !newRowIds.isEmpty }

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

    @discardableResult
    func connect(config: ConnectionConfig, password: String) async -> Bool {
        isConnecting = true
        connectionError = nil
        statusMessage = "Connecting to \(config.host)…"

        do {
            let pool = ConnectionPool(config: config, password: password)
            try await pool.connect()

            // Save to Keychain for persistence across app launches
            do {
                try KeychainService.savePassword(password, account: config.keychainAccount)
            } catch {
                print("[Glint] Keychain save failed: \(error.localizedDescription) — password kept in memory only")
            }

            // Always keep the password in memory for the active session
            activeSessionPassword = password

            connectionPool = pool
            activeConnectionId = config.id
            currentDatabase = config.database
            statusMessage = "Connected to \(config.database)"
            await loadDatabases()
            await loadSchema()
            isConnecting = false
            return true
        } catch {
            connectionError = error.localizedDescription
            statusMessage = "Connection failed"
            connectionPool = nil
            activeConnectionId = nil
            activeSessionPassword = nil
            isConnecting = false
            return false
        }
    }

    func disconnect() async {
        isConnecting = false
        connectionError = nil
        
        // Disconnect all unique pools across all tabs
        var disconnectedPools = Set<ObjectIdentifier>()
        for tab in workspaceTabs {
            guard let pool = tab.connectionPool else { continue }
            let id = ObjectIdentifier(pool)
            if !disconnectedPools.contains(id) {
                disconnectedPools.insert(id)
                await pool.disconnectAll()
            }
        }
        
        activeConnectionId = nil
        activeSessionPassword = nil
        
        resetTabs()
        resetSchemaCaches()
        statusMessage = "Disconnected"
    }

    func resetTabs() {
        var defaultTab = WorkspaceTab()
        // Ensure the default tab has no connection
        defaultTab.connectionPool = nil
        workspaceTabs = [defaultTab]
        activeWorkspaceTabId = defaultTab.id
    }

    private func resetSchemaCaches() {
        enumTypesCache = [:]
        foreignKeysBySchema = [:]
        tableColumnsCache = [:]
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
        guard let config = activeConfig else { return }
        
        // Use the actual pool configuration to determine if a switch is necessary,
        // avoiding the SwiftUI bug where `currentDatabase` is prematurely mutated.
        if let currentPool = connectionPool, currentPool.config.database == dbName {
            return
        }

        // Use in-memory password first, fall back to Keychain
        let password: String
        if let sessionPw = activeSessionPassword {
            password = sessionPw
        } else if let keychainPw = try? KeychainService.readPassword(account: config.keychainAccount) {
            password = keychainPw
        } else {
            print("[Glint] switchDatabase: no password available (memory or keychain)")
            statusMessage = "Cannot switch: password not found. Disconnect and reconnect."
            connectionError = "Password not available."
            return
        }

        print("[Glint] Switching to \(dbName) in current tab")

        // Keep isConnected == true during the switch so the sidebar
        // doesn't get destroyed and rebuilt (which kills the picker).
        isSwitchingDatabase = true
        isConnecting = true
        statusMessage = "Switching to \(dbName)…"

        // Cancel any in-flight data fetch
        activeFetchTask?.cancel()
        activeFetchTask = nil

        // Fully tear down the old connection FIRST if no other tab is using it!
        let oldPool = connectionPool
        connectionPool = nil
        if let oldPool {
            await disconnectPoolIfNeeded(oldPool)
        }

        let newConfig = ConnectionConfig(
            id: config.id,
            name: config.name,
            host: config.host,
            port: config.port,
            database: dbName,
            user: config.user,
            useSSL: config.useSSL,
            sshTunnel: config.sshTunnel,
            colorTag: config.colorTag
        )

        do {
            let newPool = ConnectionPool(config: newConfig, password: password)
            try await newPool.connect()

            connectionPool = newPool
            currentDatabase = dbName

            if let i = savedConnections.firstIndex(where: { $0.id == config.id }) {
                savedConnections[i] = newConfig
                persistConnections()
            }

            resetSchemaCaches()
            schemas = []
            selectedTable = nil
            selectedFunction = nil

            // Reload the schema for the new database (only for THIS tab)
            await loadSchema()
            // Reload the database list (new DB might have different access)
            await loadDatabases()
            statusMessage = "Connected to \(dbName)"
            print("[Glint] Successfully switched to \(dbName) — \(schemas.flatMap(\.tables).count) tables loaded")
        } catch {
            print("[Glint] switchDatabase failed: \(error)")
            statusMessage = "Failed to switch: \(error.localizedDescription)"
            connectionError = error.localizedDescription
            // Try to reconnect to the original database
            do {
                let fallbackPool = ConnectionPool(config: config, password: password)
                try await fallbackPool.connect()
                connectionPool = fallbackPool
                currentDatabase = config.database
                await loadSchema()
                statusMessage = "Switch failed, reconnected to \(config.database)"
            } catch {
                statusMessage = "Connection lost: \(error.localizedDescription)"
                isSwitchingDatabase = false
            }
        }

        isConnecting = false
        isSwitchingDatabase = false
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
            let schemaNames: [String] = schemaInfos.isEmpty ? ["public"] : schemaInfos.map(\.name)

            // PERF-04: Fetch tables and functions for all schemas in parallel
            var loaded: [DatabaseSchemaInfo] = []
            try await withThrowingTaskGroup(of: DatabaseSchemaInfo.self) { group in
                for name in schemaNames {
                    group.addTask {
                        // Fetch concurrently within the schema
                        async let tables = introspector.fetchTables(schema: name)
                        async let functions = introspector.fetchFunctions(schema: name)
                        return try await DatabaseSchemaInfo(name: name, tables: tables, functions: functions)
                    }
                }
                for try await schema in group {
                    loaded.append(schema)
                }
            }
            // Sort to maintain stable ordering: 'public' first, system schemas last, others alphabetical
            schemas = loaded.sorted { lhs, rhs in
                func sortWeight(_ name: String) -> Int {
                    if name == "public" { return 0 }
                    if name == "pg_catalog" || name == "information_schema" { return 2 }
                    return 1
                }
                let w1 = sortWeight(lhs.name)
                let w2 = sortWeight(rhs.name)
                if w1 == w2 { return lhs.name < rhs.name }
                return w1 < w2
            }

            tableColumnsCache = [:]
            foreignKeysBySchema = [:]
            enumTypesCache = (try? await introspector.fetchEnumTypes()) ?? [:]

            let tableCount = schemas.flatMap(\.tables).count
            statusMessage = "\(tableCount) table\(tableCount == 1 ? "" : "s")"
        } catch {
            statusMessage = "Schema load failed: \(error.localizedDescription)"
        }

        isLoadingSchema = false
    }

    /// Lazily fetch & cache columns, enums, and FKs for a single table.
    private func ensureTableColumns(_ table: TableInfo) async -> TableInfo {
        if let cached = tableColumnsCache[table.id], !cached.isEmpty {
            var t = table
            t.columns = cached
            return t
        }
        guard let pool = connectionPool else { return table }
        do {
            let conn = try await pool.getConnection()
            let introspector = SchemaIntrospector(connection: conn)

            var columns = try await introspector.fetchColumns(schema: table.schema, table: table.name)

            for i in columns.indices where columns[i].dataType.lowercased() == "user-defined" {
                columns[i].enumValues = enumTypesCache[columns[i].udtName]
            }

            let fks: [SchemaIntrospector.FKResult]
            if let cached = foreignKeysBySchema[table.schema] {
                fks = cached
            } else {
                fks = (try? await introspector.fetchForeignKeys(schema: table.schema)) ?? []
                foreignKeysBySchema[table.schema] = fks
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

            tableColumnsCache[table.id] = columns
            var t = table
            t.columns = columns
            return t
        } catch {
            return table
        }
    }

    // MARK: - Data Fetching

    func fetchTableData() async {
        // BUG-03: Cancel any in-flight fetch to prevent stale data overwrites
        activeFetchTask?.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard let pool = connectionPool, let table = selectedTable else { return }
            isLoadingData = true

            do {
                guard !Task.isCancelled else { return }
                let conn = try await pool.getConnection()
                let fetcher = DataFetcher(connection: conn)
                let result = try await fetcher.fetch(
                    table: table,
                    filters: filters,
                    globalSearch: globalSearchText.isEmpty ? nil : globalSearchText,
                    orderBy: orderByColumn,
                    ascending: orderAscending,
                    pageSize: pageSize,
                    offset: (currentPage - 1) * pageSize
                )
                // Only apply results if this task wasn't cancelled while awaiting
                guard !Task.isCancelled else { return }
                queryResult = result
                statusMessage = "\(queryResult.totalCount) rows · \(String(format: "%.1f", queryResult.executionTimeMs))ms"
            } catch {
                guard !Task.isCancelled else { return }
                statusMessage = "Query failed: \(error.localizedDescription)"
            }

            isLoadingData = false
        }
        activeFetchTask = task
        await task.value
    }

    func selectTable(_ table: TableInfo) async {
        selectedFunction = nil
        selectedTable = table // Set immediately to eliminate SwiftUI binding flash
        
        currentPage = 1
        filters = []
        globalSearchText = ""
        orderByColumn = nil
        orderAscending = true
        pendingEdits = []
        
        let enriched = await ensureTableColumns(table)
        // Only update and fetch if the user hasn't rapidly clicked a different table
        if selectedTable?.id == table.id {
            selectedTable = enriched
            await fetchTableData()
        }
    }

    func selectFunction(_ function: FunctionInfo) {
        selectedTable = nil
        selectedFunction = function
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

    // MARK: - Query Editor

    func toggleQueryEditor() {
        isQueryEditorOpen.toggle()
        if isQueryEditorOpen {
            selectedTable = nil
            selectedFunction = nil
        }
    }

    func executeCustomQuery(_ sql: String) async {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let pool = connectionPool else {
            queryExecutionError = "No active database connection."
            return
        }

        // SECURITY: Reject multi-statement queries in read-only mode.
        if !queryWriteMode {
            let statementsOutsideStrings = trimmed.replacingOccurrences(
                of: "'[^']*'", with: "", options: .regularExpression
            )
            let semicolonCount = statementsOutsideStrings.filter({ $0 == ";" }).count
            // Allow a trailing semicolon (common habit) but reject more
            let strippedTrailing = statementsOutsideStrings.trimmingCharacters(in: .whitespacesAndNewlines)
            let endsWithSemicolon = strippedTrailing.hasSuffix(";")
            if semicolonCount > (endsWithSemicolon ? 1 : 0) {
                queryExecutionError = "Multi-statement queries are not allowed in Read Only mode. Enable Write Mode to execute multiple statements."
                return
            }
        }

        isExecutingQuery = true
        queryExecutionError = nil
        customQueryResult = nil

        let startTime = CFAbsoluteTimeGetCurrent()
        let maxRows = 10_000 // Safety cap to prevent OOM on production databases

        do {
            let conn = try await pool.getConnection()

            // Safety: wrap in a read-only transaction unless write mode is enabled
            if !queryWriteMode {
                try await conn.execute("BEGIN READ ONLY")
            }

            do {
                let rowSequence = try await conn.query(trimmed)
                var rawRows: [PostgresRow] = []
                var truncated = false
                for try await row in rowSequence {
                    if rawRows.count >= maxRows {
                        truncated = true
                        continue
                    }
                    rawRows.append(row)
                }
                let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

                // Materialize columns from the first row
                let columns: [ColumnInfo]
                if let firstRow = rawRows.first {
                    let cells = firstRow.makeRandomAccess()
                    columns = (0..<cells.count).map { i in
                        ColumnInfo(
                            name: cells[i].columnName,
                            tableName: "",
                            dataType: "text",
                            udtName: "text",
                            isNullable: true,
                            isPrimaryKey: false,
                            hasDefault: false,
                            defaultValue: nil,
                            characterMaxLength: nil,
                            numericPrecision: nil,
                            ordinalPosition: i
                        )
                    }
                } else {
                    columns = []
                }

                // Materialize rows
                let rows: [TableRow] = rawRows.map { pgRow in
                    let cells = pgRow.makeRandomAccess()
                    let values = (0..<cells.count).map { i -> CellValue in
                        let cell = cells[i]
                        let rawValue: String?
                        if var bytes = cell.bytes {
                            // Try String decode first; fall back to raw bytes for
                            // date, timestamp, bytea, uuid, and other non-text types
                            if let str = try? cell.decode(String.self) {
                                rawValue = str
                            } else {
                                rawValue = bytes.readString(length: bytes.readableBytes)
                            }
                        } else {
                            rawValue = nil
                        }
                        return CellValue(
                            columnName: cell.columnName,
                            rawValue: rawValue,
                            dataType: cell.dataType.rawValue.description
                        )
                    }
                    return TableRow(values: values)
                }

                if !queryWriteMode {
                    try await conn.execute("COMMIT")
                }

                let displayQuery = truncated
                    ? "\(trimmed)\n-- Results truncated to \(maxRows) rows"
                    : trimmed

                let result = QueryResult(
                    rows: rows,
                    columns: columns,
                    totalCount: Int64(rows.count),
                    pageSize: rows.count,
                    currentOffset: 0,
                    executionTimeMs: durationMs,
                    query: displayQuery
                )
                customQueryResult = result

                // Record to history
                queryHistory.insert(QueryHistoryEntry(
                    sql: trimmed,
                    durationMs: durationMs,
                    rowCount: Int64(rows.count)
                ), at: 0)

                // Cap history at 50 entries
                if queryHistory.count > 50 {
                    queryHistory = Array(queryHistory.prefix(50))
                }
            } catch {
                if !queryWriteMode {
                    _ = try? await conn.execute("ROLLBACK")
                }
                throw error
            }
        } catch {
            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            queryExecutionError = error.localizedDescription

            queryHistory.insert(QueryHistoryEntry(
                sql: trimmed,
                durationMs: durationMs,
                wasError: true,
                errorMessage: error.localizedDescription
            ), at: 0)

            if queryHistory.count > 50 {
                queryHistory = Array(queryHistory.prefix(50))
            }
        }

        isExecutingQuery = false
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
        guard let pool = connectionPool, let table = selectedTable, hasPendingEdits else { return }

        let editsByRow = Dictionary(grouping: pendingEdits) { $0.rowId }
        let qTable = "\(SQLSanitizer.quoteIdentifier(table.schema)).\(SQLSanitizer.quoteIdentifier(table.name))"

        // BUG-07: Collect ALL primary key columns for composite PK support
        let pkColumns = table.columns.filter { $0.isPrimaryKey }
        let pkIndices = table.columns.enumerated().filter { $0.element.isPrimaryKey }.map { $0.offset }

        do {
            let conn = try await pool.getConnection()

            // SAFE-04: Wrap all edits in a transaction for atomic commit/rollback
            try await conn.execute("BEGIN")

            do {
                for (rowId, edits) in editsByRow {
                    guard let originalRow = queryResult.rows.first(where: { $0.id == rowId }) else { continue }

                    let isNewRow = newRowIds.contains(rowId)

                    if isNewRow {
                        // BUG-05: Generate INSERT for new rows
                        let allEdits = edits.filter { $0.newValue != nil }

                        let sql: String
                        if allEdits.isEmpty {
                            sql = "INSERT INTO \(qTable) DEFAULT VALUES"
                        } else {
                            let colNames = allEdits.map { SQLSanitizer.quoteIdentifier($0.columnName) }
                            let colValues = allEdits.map { edit -> String in
                                if let value = edit.newValue {
                                    return SQLSanitizer.quoteLiteral(value)
                                }
                                return "NULL"
                            }
                            sql = "INSERT INTO \(qTable) (\(colNames.joined(separator: ", "))) VALUES (\(colValues.joined(separator: ", ")))"
                        }
                        
                        try await conn.execute(sql)
                    } else {
                        // UPDATE existing row
                        let setClauses = edits.compactMap { edit -> String? in
                            guard edit.hasChanged else { return nil }
                            let qCol = SQLSanitizer.quoteIdentifier(edit.columnName)
                            if let newValue = edit.newValue {
                                return "\(qCol) = \(SQLSanitizer.quoteLiteral(newValue))"
                            }
                            return "\(qCol) = NULL"
                        }

                        guard !setClauses.isEmpty else { continue }

                        // BUG-07: Build compound WHERE clause for all PK columns
                        let whereConditions: [String]
                        if !pkColumns.isEmpty {
                            whereConditions = zip(pkColumns, pkIndices).compactMap { (pkCol, pkIdx) -> String? in
                                guard let pkValue = originalRow[pkIdx]?.rawValue else { return nil }
                                return "\(SQLSanitizer.quoteIdentifier(pkCol.name)) = \(SQLSanitizer.quoteLiteral(pkValue))"
                            }
                        } else {
                            // No PK — skip this row to avoid updating all rows
                            statusMessage = "Cannot update row: table has no primary key"
                            continue
                        }

                        guard whereConditions.count == pkColumns.count else {
                            statusMessage = "Cannot update row: primary key value is NULL"
                            continue
                        }

                        // SAFE-03: Use RETURNING to verify exactly 1 row was affected
                        let returningCols = pkColumns.map { SQLSanitizer.quoteIdentifier($0.name) }.joined(separator: ", ")
                        let sql = "UPDATE \(qTable) SET \(setClauses.joined(separator: ", ")) WHERE \(whereConditions.joined(separator: " AND ")) RETURNING \(returningCols)"
                        print("[Glint] Executing UPDATE: \(sql)")

                        let resultRows = try await conn.queryAll(sql)
                        if resultRows.count != 1 {
                            throw PostgresConnection.ConnectionError.queryFailed(
                                "Expected to update 1 row but affected \(resultRows.count) rows"
                            )
                        }
                    }
                }

                try await conn.execute("COMMIT")
                print("[Glint] Transaction committed: \(editsByRow.count) row(s) updated")
            } catch {
                // SAFE-04: Rollback on any error
                _ = try? await conn.execute("ROLLBACK")
                throw error
            }

            pendingEdits.removeAll()
            newRowIds.removeAll()
            statusMessage = "Changes committed"
            await fetchTableData()
        } catch {
            print("[Glint] Commit failed: \(error)")
            statusMessage = "Commit failed: \(error.localizedDescription)"
        }
    }

    func discardEdits() {
        if !newRowIds.isEmpty {
            let idsToRemove = newRowIds
            queryResult = QueryResult(
                rows: queryResult.rows.filter { !idsToRemove.contains($0.id) },
                columns: queryResult.columns,
                totalCount: max(0, queryResult.totalCount - Int64(idsToRemove.count)),
                pageSize: queryResult.pageSize,
                currentOffset: queryResult.currentOffset,
                executionTimeMs: queryResult.executionTimeMs,
                query: queryResult.query
            )
        }
        pendingEdits.removeAll()
        newRowIds.removeAll()
        statusMessage = "Changes discarded"
    }

    func deleteSelectedRows() async {
        guard let pool = connectionPool, let table = selectedTable, !selectedRowIds.isEmpty else { return }

        let pkColumns = table.columns.filter { $0.isPrimaryKey }
        guard !pkColumns.isEmpty else {
            statusMessage = "Cannot delete: table has no primary key."
            return
        }

        let qTable = "\(SQLSanitizer.quoteIdentifier(table.schema)).\(SQLSanitizer.quoteIdentifier(table.name))"
        let pkIndices = table.columns.enumerated().filter { $0.element.isPrimaryKey }.map { $0.offset }

        // Find the rows matching the selected IDs
        let rowsToDelete = queryResult.rows.filter { selectedRowIds.contains($0.id) }
        guard !rowsToDelete.isEmpty else { return }

        do {
            let conn = try await pool.getConnection()
            try await conn.execute("BEGIN")

            for row in rowsToDelete {
                let whereConditions = zip(pkColumns, pkIndices).compactMap { (pkCol, pkIdx) -> String? in
                    guard let pkValue = row[pkIdx]?.rawValue else { return nil }
                    return "\(SQLSanitizer.quoteIdentifier(pkCol.name)) = \(SQLSanitizer.quoteLiteral(pkValue))"
                }

                guard whereConditions.count == pkColumns.count else {
                    throw PostgresConnection.ConnectionError.queryFailed("Cannot delete row with NULL primary key")
                }

                let sql = "DELETE FROM \(qTable) WHERE \(whereConditions.joined(separator: " AND "))"
                try await conn.execute(sql)
            }

            try await conn.execute("COMMIT")
            selectedRowIds.removeAll()
            statusMessage = "Deleted \(rowsToDelete.count) row(s)"
            await fetchTableData()
        } catch {
            _ = try? await pool.getConnection().execute("ROLLBACK")
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func insertNewRow() {
        guard let table = selectedTable else { return }
        let newRow = TableRow(values: table.columns.map {
            CellValue(columnName: $0.name, rawValue: nil, dataType: $0.udtName)
        })
        // BUG-05: Track this as a new row so commitEdits generates INSERT
        newRowIds.insert(newRow.id)
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

    func duplicateRow(at index: Int) async {
        guard let table = selectedTable,
              index >= 0, index < queryResult.rows.count else { return }
        
        let originalRow = queryResult.rows[index]
        let duplicatedValues = table.columns.enumerated().map { (colIdx, col) -> CellValue in
            if col.isPrimaryKey {
                return CellValue(columnName: col.name, rawValue: nil, dataType: col.udtName)
            }
            guard colIdx < originalRow.values.count else {
                return CellValue(columnName: col.name, rawValue: nil, dataType: col.udtName)
            }
            return CellValue(columnName: col.name, rawValue: originalRow.values[colIdx].rawValue, dataType: col.udtName)
        }
        
        let newRow = TableRow(values: duplicatedValues)
        newRowIds.insert(newRow.id)
        
        queryResult = QueryResult(
            rows: [newRow] + queryResult.rows,
            columns: queryResult.columns,
            totalCount: queryResult.totalCount + 1,
            pageSize: queryResult.pageSize,
            currentOffset: queryResult.currentOffset,
            executionTimeMs: queryResult.executionTimeMs,
            query: queryResult.query
        )
        
        for (colIdx, cell) in newRow.values.enumerated() {
            if let value = cell.rawValue {
                pendingEdits.append(PendingEdit(
                    rowId: newRow.id,
                    columnIndex: colIdx,
                    columnName: cell.columnName,
                    originalValue: nil,
                    newValue: value
                ))
            }
        }
        
        statusMessage = "Row duplicated — edit values and save"
    }

    // MARK: - Export

    func exportTableAsCSV() async {
        guard let pool = connectionPool, let table = selectedTable else { return }
        
        isExporting = true
        statusMessage = "Preparing CSV Export..."
        
        do {
            let conn = try await pool.getConnection()
            let builder = QueryBuilder()
            
            // Build the query WITHOUT limit/offset to fetch the entire matching dataset
            let (sql, _) = builder.buildQuery(
                table: table,
                filters: filters,
                globalSearch: globalSearchText.isEmpty ? nil : globalSearchText,
                orderBy: orderByColumn,
                ascending: orderAscending,
                limit: nil,
                offset: 0
            )
            
            statusMessage = "Select save location..."
            try await CSVExporter.exportStreamToCSV(connection: conn, sql: sql, tableName: table.name)
            
            statusMessage = "Export complete!"
        } catch let error as CSVExportError {
            statusMessage = error.localizedDescription
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
        
        isExporting = false
    }

    // MARK: - Schema Refresh

    func loadColumnsForTable(_ table: TableInfo) async -> TableInfo? {
        let enriched = await ensureTableColumns(table)
        return enriched.columns.isEmpty ? nil : enriched
    }
}

// MARK: - Sidebar Item

enum SidebarItem: Hashable {
    case connection(UUID)
    case schema(String)
    case table(TableInfo)
}

enum ContentTab: String, CaseIterable {
    case content = "Content"
    case structure = "Structure"
    case ddl = "DDL"
}
