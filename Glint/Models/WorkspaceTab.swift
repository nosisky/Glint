//
//  WorkspaceTab.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation

struct WorkspaceTab: Identifiable, Hashable, Equatable {
    let id: UUID
    var selectedTable: TableInfo?
    var selectedFunction: FunctionInfo?
    // Connection State
    var connectionPool: ConnectionPool?
    var currentDatabase: String = ""
    var databases: [String] = []
    
    // Schema State
    var schemas: [DatabaseSchemaInfo] = []
    var isLoadingSchema = false
    var selectedSchema: String = "public"
    
    // Data Grid
    var queryResult: QueryResult = .empty
    var isLoadingData = false
    var currentPage = 1
    
    // Filters
    var filters: [FilterConstraint] = []
    var globalSearchText = ""
    var orderByColumn: String?
    var orderAscending = true
    
    // Editing
    var pendingEdits: [PendingEdit] = []
    var editingCellId: String?
    var newRowIds: Set<UUID> = []
    var selectedRowIds: Set<UUID> = []
    
    // Query Editor
    var isQueryEditorOpen = false
    var customQueryText: String = ""
    var customQueryResult: QueryResult?
    var customQueryPage: Int = 1
    var customQueryPageSize: Int = 200
    var queryExecutionError: String?
    var isExecutingQuery = false
    var queryWriteMode = false
    var queryHistory: [QueryHistoryEntry] = []
    
    // Explain
    var explainResult: ExplainPlan?
    var isExplaining = false
    
    // Activity Monitor
    var isActivityMonitorOpen = false
    var backendActivities: [PgBackendActivity] = []
    
    // UI State
    var activeTab: ContentTab = .content
    
    var title: String {
        if isActivityMonitorOpen { return "Activity Monitor" }
        if let table = selectedTable { return table.name }
        if let function = selectedFunction { return function.name }
        return "New Tab"
    }
    
    init(id: UUID = UUID()) {
        self.id = id
    }
    
    static func == (lhs: WorkspaceTab, rhs: WorkspaceTab) -> Bool {
        lhs.id == rhs.id && 
        lhs.selectedTable?.name == rhs.selectedTable?.name &&
        lhs.selectedFunction?.name == rhs.selectedFunction?.name &&
        lhs.activeTab == rhs.activeTab
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(selectedTable?.name)
        hasher.combine(selectedFunction?.name)
        hasher.combine(activeTab)
    }
}
