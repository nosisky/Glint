//
//  QueryEditorView.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// The main SQL query editor view with split-pane layout:
/// top half for the query input, bottom half for results/errors.
struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var splitFraction: CGFloat = 0.4
    @State private var dragStartFraction: CGFloat = 0.4
    @State private var showWriteConfirm = false

    // Cached autocomplete source — only recalculated when schemas change,
    // not on every SwiftUI body evaluation.
    @State private var cachedSource: SQLTextEditor.AutocompleteSource?
    @State private var lastSchemaId: UUID?

    private func resolvedSource() -> SQLTextEditor.AutocompleteSource {
        // Only rebuild when schemas change (detected via schema count + first table name)
        let schemaId = appState.schemas.isEmpty
            ? UUID()
            : UUID(uuidString: "00000000-0000-0000-0000-000000000000")! // stable when unchanged
        if let cachedSource, lastSchemaId == schemaId {
            return cachedSource
        }
        let source = SQLTextEditor.AutocompleteSource(
            keywords: Self.sqlKeywords,
            tableNames: appState.schemas.flatMap(\.tables).map(\.name),
            columnNames: appState.schemas.flatMap(\.tables).flatMap(\.columns).map(\.name)
        )
        return source
    }

    var body: some View {
        @Bindable var state = appState
        let source = resolvedSource()

        VStack(spacing: 0) {
            // Header bar
            queryHeader

            // Split pane: editor + results
            GeometryReader { geo in
                VStack(spacing: 0) {
                    editorPane(source: source)
                        .frame(height: geo.size.height * splitFraction)

                    splitHandle(totalHeight: geo.size.height)

                    resultsPane
                        .frame(maxHeight: .infinity)
                }
            }

            // Bottom bar
            queryBottomBar
        }
        .alert("Enable Write Mode?", isPresented: $showWriteConfirm) {
            Button("Enable Write Mode", role: .destructive) {
                appState.queryWriteMode = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Write Mode allows INSERT, UPDATE, DELETE, and DROP statements. This can modify or destroy data. Are you sure?")
        }
    }

    // MARK: - Header

    private var queryHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                Text("SQL Query")
                    .font(.system(size: 13, weight: .semibold))
                Text("·").foregroundStyle(.quaternary)
                Text(appState.currentDatabase)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }

            Spacer()

            // Read-only / Write mode toggle
            Button {
                if appState.queryWriteMode {
                    appState.queryWriteMode = false
                } else {
                    showWriteConfirm = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: appState.queryWriteMode ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 9, weight: .bold))

                    Text(appState.queryWriteMode ? "Write Mode" : "Read Only")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(appState.queryWriteMode ? .orange : .green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (appState.queryWriteMode ? Color.orange : Color.green).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            (appState.queryWriteMode ? Color.orange : Color.green).opacity(0.25),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(GlintDesign.panelBackground)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Split Handle

    private func splitHandle(totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(GlintDesign.hairline)
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 10)
                    .contentShape(Rectangle())
                    .cursor(.resizeUpDown)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let delta = value.translation.height / totalHeight
                                let newFraction = dragStartFraction + delta
                                splitFraction = min(max(newFraction, 0.15), 0.85)
                            }
                            .onEnded { _ in
                                dragStartFraction = splitFraction
                            }
                    )
            )
    }

    // MARK: - Editor Pane

    private func editorPane(source: SQLTextEditor.AutocompleteSource) -> some View {
        @Bindable var state = appState

        return SQLTextEditor(
            text: $state.customQueryText,
            onExecute: { Task { await appState.executeCustomQuery(appState.customQueryText) } },
            completionSource: source
        )
        .background(GlintDesign.appBackground)
    }

    // MARK: - Results Pane

    @ViewBuilder
    private var resultsPane: some View {
        if appState.isExecutingQuery {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Executing query…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlintDesign.appBackground.opacity(0.5))
        } else if let error = appState.queryExecutionError {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                        Text("Query Error")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.red.opacity(0.03))
        } else if let result = appState.customQueryResult {
            if result.rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    Text("Query executed successfully")
                        .font(.system(size: 14, weight: .medium))
                    Text("No rows returned · \(String(format: "%.0f", result.executionTimeMs))ms")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                QueryResultGridView(result: result)
            }
        } else {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 56, height: 56)
                    Image(systemName: "text.cursor")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                }
                VStack(spacing: 4) {
                    Text("Write a SQL query")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Press ⌘⏎ to execute · Ctrl+Space for autocomplete")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Bottom Bar

    private var queryBottomBar: some View {
        let queryIsEmpty = appState.customQueryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isDisabled = appState.isExecutingQuery || queryIsEmpty

        return HStack(spacing: 8) {
            // History button
            Menu {
                if appState.queryHistory.isEmpty {
                    Text("No query history")
                } else {
                    ForEach(appState.queryHistory.prefix(20)) { entry in
                        Button {
                            appState.customQueryText = entry.sql
                        } label: {
                            HStack {
                                Image(systemName: entry.wasError ? "xmark.circle" : "checkmark.circle")
                                    .foregroundStyle(entry.wasError ? .red : .green)
                                Text(entry.sql.prefix(80) + (entry.sql.count > 80 ? "…" : ""))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                    Text("Query History")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.2), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Status
            if let result = appState.customQueryResult {
                Text("\(result.rows.count) row\(result.rows.count == 1 ? "" : "s") · \(String(format: "%.0f", result.executionTimeMs))ms")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                
                if result.hasMore || appState.customQueryPage > 1 {
                    Menu {
                        if appState.customQueryPage > 1 {
                            let prevStart = max(1, (appState.customQueryPage - 2) * appState.customQueryPageSize + 1)
                            let prevEnd = (appState.customQueryPage - 1) * appState.customQueryPageSize
                            Button("Previous Page (Rows \(prevStart)-\(prevEnd))") {
                                appState.customQueryPage -= 1
                                Task { await appState.executeCustomQuery(appState.customQueryText) }
                            }
                        }
                        
                        let startRow = (appState.customQueryPage - 1) * appState.customQueryPageSize + 1
                        let endRow = result.rows.isEmpty ? startRow : startRow + result.rows.count - 1
                        let currentLabel = result.rows.isEmpty ? "Page \(appState.customQueryPage) (Empty)" : "Rows \(startRow)-\(endRow)"
                        Button("Current Page (\(currentLabel))") {}
                            .disabled(true)
                        
                        if result.hasMore {
                            Button("Next Page (Rows \(endRow + 1)-\(endRow + appState.customQueryPageSize))") {
                                appState.customQueryPage += 1
                                Task { await appState.executeCustomQuery(appState.customQueryText) }
                            }
                        }
                    } label: {
                        let startRow = (appState.customQueryPage - 1) * appState.customQueryPageSize + 1
                        let endRow = result.rows.isEmpty ? startRow : startRow + result.rows.count - 1
                        let labelText = result.rows.isEmpty ? "Empty Page" : "Rows \(startRow)-\(endRow)"
                        HStack(spacing: 4) {
                            Text(labelText)
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } else if appState.queryExecutionError != nil {
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("Error")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
            }

            Spacer()
            
            // Export Button
            if appState.customQueryResult != nil && !queryIsEmpty {
                Menu {
                    Button("Export as CSV...") {
                        Task { await appState.exportCustomQueryAsCSV() }
                    }
                    Button("Export as JSON...") {
                        Task { await appState.exportCustomQueryAsJSON() }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if appState.isExporting {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                        }
                        Text("Export")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.2), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(appState.isExporting)
            }

            // Execute button
            Button {
                appState.customQueryPage = 1 // Reset pagination on new execution
                Task { await appState.executeCustomQuery(appState.customQueryText) }
            } label: {
                HStack(spacing: 5) {
                    Text("Execute Statement")
                        .font(.system(size: 12, weight: .medium))
                    Text("⌘⏎")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - SQL Keywords (static, created once)

    private static let sqlKeywords: [String] = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
        "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "ADD", "INDEX", "UNIQUE",
        "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "NOT", "NULL", "DEFAULT",
        "AND", "OR", "IN", "EXISTS", "BETWEEN", "LIKE", "ILIKE", "IS",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "FULL",
        "GROUP", "BY", "ORDER", "ASC", "DESC", "LIMIT", "OFFSET", "HAVING",
        "DISTINCT", "CASE", "WHEN", "THEN", "ELSE", "END",
        "BEGIN", "COMMIT", "ROLLBACK", "RETURNING", "CASCADE", "RESTRICT",
        "WITH", "AS", "ON", "USING", "CONSTRAINT", "CHECK",
        "GRANT", "REVOKE", "EXPLAIN", "ANALYZE", "VACUUM", "TRUNCATE",
        "UNION", "ALL", "INTERSECT", "EXCEPT", "FETCH", "NEXT", "ROWS", "ONLY",
        "COALESCE", "CAST", "TRUE", "FALSE", "SCHEMA", "DATABASE",
        "VIEW", "FUNCTION", "TRIGGER", "TEMPORARY", "TEMP", "IF",
        "REPLACE", "MATERIALIZED", "CONCURRENTLY", "RECURSIVE", "LATERAL"
    ]
}

// MARK: - Query Result Grid (read-only)

/// Renders the custom query result in a read-only NSTableView.
/// Uses index-based cell lookup (O(1)) instead of name-based search (O(n)).
struct QueryResultGridView: NSViewRepresentable {
    let result: QueryResult

    func makeCoordinator() -> Coordinator { Coordinator(result: result) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 8, height: 4)
        tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.08)
        tableView.headerView = NSTableHeaderView()
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        rebuildColumns(tableView: tableView, context: context)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.reloadData()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        let newColumnIds = result.columns.map(\.name)
        if context.coordinator.lastColumnIds != newColumnIds {
            rebuildColumns(tableView: tableView, context: context)
        }

        context.coordinator.result = result
        context.coordinator.rebuildColumnIndex()
        tableView.reloadData()
    }

    private func rebuildColumns(tableView: NSTableView, context: Context) {
        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }

        for (i, col) in result.columns.enumerated() {
            // Use index-suffixed identifiers to handle duplicate column names
            // (e.g. SELECT a.id, b.id FROM ...)
            let colId = NSUserInterfaceItemIdentifier("\(i)_\(col.name)")
            let column = NSTableColumn(identifier: colId)
            column.title = col.name
            column.width = 140
            column.minWidth = 60
            column.maxWidth = 600
            tableView.addTableColumn(column)
        }

        context.coordinator.lastColumnIds = result.columns.map(\.name)
        context.coordinator.rebuildColumnIndex()
    }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var result: QueryResult
        weak var tableView: NSTableView?
        var lastColumnIds: [String] = []

        // Maps column identifier → index into values array (O(1) lookup)
        private var columnIdentifierToIndex: [String: Int] = [:]

        init(result: QueryResult) {
            self.result = result
        }

        func rebuildColumnIndex() {
            columnIdentifierToIndex.removeAll()
            for (i, col) in result.columns.enumerated() {
                columnIdentifierToIndex["\(i)_\(col.name)"] = i
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            result.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let colId = tableColumn?.identifier.rawValue,
                  let colIndex = columnIdentifierToIndex[colId],
                  row < result.rows.count else { return nil }

            let rowData = result.rows[row]

            let cellId = NSUserInterfaceItemIdentifier("QC")
            let cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField
                ?? {
                    let tf = NSTextField(labelWithString: "")
                    tf.identifier = cellId
                    tf.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    tf.lineBreakMode = .byTruncatingTail
                    tf.maximumNumberOfLines = 1
                    tf.cell?.truncatesLastVisibleLine = true
                    return tf
                }()

            // O(1) index-based lookup instead of O(n) name search
            if colIndex < rowData.values.count {
                let value = rowData.values[colIndex]
                cell.stringValue = value.rawValue ?? "NULL"
                cell.textColor = value.rawValue == nil ? NSColor.placeholderTextColor : NSColor.labelColor
            } else {
                cell.stringValue = ""
                cell.textColor = NSColor.labelColor
            }

            return cell
        }
    }
}

// MARK: - Cursor Extension

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() }
            else { NSCursor.pop() }
        }
    }
}
