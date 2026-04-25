import SwiftUI

/// Container — data/structure tab + grid + pagination.
struct DataGridContainer: View {
    @Environment(AppState.self) private var appState
    @State private var showStructure = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            GridToolbar(showStructure: $showStructure)

            if showStructure {
                if let table = appState.selectedTable {
                    TableStructureView(table: table)
                }
            } else {
                // Filters
                if appState.hasActiveFilters {
                    ActiveFiltersBar()
                }

                // Grid
                DataGridView()

                // Footer
                GridFooter()
            }
        }
    }
}

// MARK: - Toolbar

private struct GridToolbar: View {
    @Binding var showStructure: Bool
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            // Data / Structure toggle
            Picker("", selection: $showStructure) {
                Text("Content").tag(false)
                Text("Structure").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()

            // Pending edits
            if appState.hasPendingEdits {
                HStack(spacing: 6) {
                    Button("Discard") {
                        appState.discardEdits()
                    }

                    Button("Save Changes") {
                        Task { await appState.commitEdits() }
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }

            Button {
                Task { await appState.fetchTableData() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Data Grid

struct DataGridView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isLoadingData && appState.queryResult.rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.queryResult.rows.isEmpty {
                ContentUnavailableView {
                    Label(appState.hasActiveFilters ? "No Results" : "Empty", systemImage: "tray")
                } description: {
                    if appState.hasActiveFilters {
                        Text("No rows match the current filters.")
                    }
                } actions: {
                    if appState.hasActiveFilters {
                        Button("Clear Filters") {
                            Task { await appState.clearAllFilters() }
                        }
                    }
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(appState.queryResult.rows.enumerated()), id: \.element.id) { index, row in
                                GridRow(row: row, columns: appState.queryResult.columns, index: index)
                            }
                        } header: {
                            HeaderRow(columns: appState.queryResult.columns)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    if appState.isLoadingData {
                        ProgressView()
                            .controlSize(.small)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Header

private struct HeaderRow: View {
    let columns: [ColumnInfo]
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns) { col in
                Button {
                    Task { await appState.toggleSort(column: col.name) }
                } label: {
                    HStack(spacing: 4) {
                        Text(col.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)

                        if appState.orderByColumn == col.name {
                            Image(systemName: appState.orderAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: GlintDesign.defaultColumnWidth, alignment: .leading)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)

                Divider()
            }
        }
        .frame(height: GlintDesign.headerHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Row

private struct GridRow: View {
    let row: TableRow
    let columns: [ColumnInfo]
    let index: Int
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(row.values.enumerated()), id: \.offset) { colIndex, cell in
                CellView(cell: cell, rowId: row.id, columnIndex: colIndex)
                    .frame(width: GlintDesign.defaultColumnWidth, alignment: .leading)

                Divider().opacity(0.3)
            }
        }
        .frame(height: GlintDesign.rowHeight)
        .background {
            if isHovered {
                Color.accentColor.opacity(0.06)
            } else if index % 2 == 1 {
                Color(nsColor: .alternatingContentBackgroundColors[1])
            }
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Cell

private struct CellView: View {
    let cell: CellValue
    let rowId: UUID
    let columnIndex: Int
    @Environment(AppState.self) private var appState
    @State private var isEditing = false
    @State private var editText = ""

    private var isPending: Bool {
        appState.pendingEdits.contains { $0.rowId == rowId && $0.columnIndex == columnIndex }
    }

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 6)
                    .onSubmit { commitEdit() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(cell.displayValue)
                    .font(.system(size: 12, design: cell.isNull ? .default : .monospaced))
                    .foregroundStyle(cell.isNull ? GlintDesign.nullText : .primary)
                    .italic(cell.isNull)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editText = cell.rawValue ?? ""
                        isEditing = true
                    }
            }
        }
        .background {
            if isPending {
                GlintDesign.pendingEditSubtle
            }
        }
    }

    private func commitEdit() {
        isEditing = false
        guard editText != (cell.rawValue ?? "") else { return }
        appState.pendingEdits.append(PendingEdit(
            rowId: rowId,
            columnIndex: columnIndex,
            columnName: cell.columnName,
            originalValue: cell.rawValue,
            newValue: editText.isEmpty ? nil : editText
        ))
    }
}

// MARK: - Footer

private struct GridFooter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            if appState.queryResult.totalCount > 0 {
                Text("\(appState.queryResult.totalCount) rows")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if appState.queryResult.executionTimeMs > 0 {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(String(format: "%.0f", appState.queryResult.executionTimeMs))ms")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if appState.queryResult.totalPages > 1 {
                HStack(spacing: 8) {
                    Button {
                        Task { await appState.previousPage() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10))
                    }
                    .disabled(appState.currentPage <= 1)

                    Text("\(appState.currentPage) / \(appState.queryResult.totalPages)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await appState.nextPage() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                    }
                    .disabled(!appState.queryResult.hasMore)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
