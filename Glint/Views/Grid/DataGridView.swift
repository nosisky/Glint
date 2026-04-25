import SwiftUI

/// Container for the data grid with toolbar actions and pagination controls.
struct DataGridContainer: View {
    @Environment(AppState.self) private var appState
    @State private var activeTab: DetailTab = .data

    enum DetailTab: String, CaseIterable {
        case data = "Data"
        case structure = "Structure"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar + commit toolbar
            DetailToolbar(activeTab: $activeTab)

            switch activeTab {
            case .data:
                // Active filters bar
                if appState.hasActiveFilters {
                    ActiveFiltersBar()
                }

                // Data grid
                DataGridView()

                // Pagination footer
                PaginationBar()

            case .structure:
                if let table = appState.selectedTable {
                    TableStructureView(table: table)
                }
            }
        }
        .background(GlintDesign.background)
    }
}

// MARK: - Detail Toolbar

struct DetailToolbar: View {
    @Binding var activeTab: DataGridContainer.DetailTab
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: GlintDesign.spacingSM) {
            // Tab picker
            Picker("", selection: $activeTab) {
                ForEach(DataGridContainer.DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()

            // Table name
            if let table = appState.selectedTable {
                HStack(spacing: GlintDesign.spacingXS) {
                    Image(systemName: table.type.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(GlintDesign.gold)
                    Text(table.name)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Commit / Discard buttons (only when there are pending edits)
            if appState.hasPendingEdits {
                HStack(spacing: GlintDesign.spacingSM) {
                    Button {
                        appState.discardEdits()
                    } label: {
                        Label("Discard", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GlintDesign.error)

                    Button {
                        Task { await appState.commitEdits() }
                    } label: {
                        Label("Commit \(appState.pendingEdits.count) Change\(appState.pendingEdits.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(GlintButtonStyle(isPrimary: true))
                    .keyboardShortcut(.return, modifiers: [.command])
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Refresh button
            Button {
                Task { await appState.fetchTableData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, GlintDesign.spacingMD)
        .padding(.vertical, GlintDesign.spacingSM)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .animation(GlintDesign.snappy, value: appState.hasPendingEdits)
    }
}

// MARK: - Data Grid

struct DataGridView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isLoadingData && appState.queryResult.rows.isEmpty {
                LoadingOverlay(message: "Fetching data…")
            } else if appState.queryResult.rows.isEmpty {
                EmptyDataView()
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(appState.queryResult.rows.enumerated()), id: \.element.id) { index, row in
                                DataGridRow(
                                    row: row,
                                    columns: appState.queryResult.columns,
                                    rowIndex: index,
                                    isAlternate: index % 2 == 1
                                )
                            }
                        } header: {
                            ColumnHeaderRow(columns: appState.queryResult.columns)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    if appState.isLoadingData {
                        ProgressView()
                            .controlSize(.small)
                            .padding(GlintDesign.spacingSM)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(GlintDesign.smooth, value: appState.isLoadingData)
    }
}

// MARK: - Column Header Row

struct ColumnHeaderRow: View {
    let columns: [ColumnInfo]
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                ColumnHeaderCell(column: column)
            }
        }
        .frame(height: GlintDesign.headerHeight)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct ColumnHeaderCell: View {
    let column: ColumnInfo
    @Environment(AppState.self) private var appState
    @State private var showFilterPopover = false
    @State private var isHovered = false

    var isSorted: Bool {
        appState.orderByColumn == column.name
    }

    var body: some View {
        Button {
            Task { await appState.toggleSort(column: column.name) }
        } label: {
            HStack(spacing: GlintDesign.spacingXS) {
                Image(systemName: column.typeIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                Text(column.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if isSorted {
                    Image(systemName: appState.orderAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(GlintDesign.gold)
                }

                Spacer()

                // Filter button (visible on hover)
                if isHovered {
                    Button {
                        showFilterPopover = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, GlintDesign.spacingSM)
        }
        .buttonStyle(.plain)
        .frame(width: GlintDesign.defaultColumnWidth, alignment: .leading)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
            ColumnFilterPopover(column: column)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(GlintDesign.separator)
                .frame(width: 1)
        }
    }
}

// MARK: - Data Row

struct DataGridRow: View {
    let row: TableRow
    let columns: [ColumnInfo]
    let rowIndex: Int
    let isAlternate: Bool
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(row.values.enumerated()), id: \.offset) { colIndex, cell in
                CellView(
                    cell: cell,
                    rowId: row.id,
                    columnIndex: colIndex,
                    isPending: hasPendingEdit(rowId: row.id, colIndex: colIndex)
                )
                .frame(width: GlintDesign.defaultColumnWidth, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(GlintDesign.separator.opacity(0.3))
                        .frame(width: 1)
                }
            }
        }
        .frame(height: GlintDesign.rowHeight)
        .background {
            if isHovered {
                Color.primary.opacity(0.04)
            } else if isAlternate {
                GlintDesign.alternatingRow.opacity(0.5)
            }
        }
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GlintDesign.separator.opacity(0.15))
                .frame(height: 1)
        }
    }

    private func hasPendingEdit(rowId: UUID, colIndex: Int) -> Bool {
        appState.pendingEdits.contains { $0.rowId == rowId && $0.columnIndex == colIndex }
    }
}

// MARK: - Cell View

struct CellView: View {
    let cell: CellValue
    let rowId: UUID
    let columnIndex: Int
    let isPending: Bool
    @Environment(AppState.self) private var appState
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, GlintDesign.spacingSM)
                    .onSubmit {
                        commitEdit()
                    }
                    .onExitCommand {
                        isEditing = false
                    }
            } else {
                Text(cell.displayValue)
                    .font(.system(size: 12, design: cell.isNull ? .default : .monospaced))
                    .foregroundStyle(cell.isNull ? GlintDesign.nullValue : GlintDesign.primaryText)
                    .italic(cell.isNull)
                    .lineLimit(1)
                    .padding(.horizontal, GlintDesign.spacingSM)
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
                RoundedRectangle(cornerRadius: 2)
                    .stroke(GlintDesign.goldBorder, lineWidth: 1.5)
                    .padding(1)
            }
        }
    }

    private func commitEdit() {
        isEditing = false
        guard editText != (cell.rawValue ?? "") else { return }

        let edit = PendingEdit(
            rowId: rowId,
            columnIndex: columnIndex,
            columnName: cell.columnName,
            originalValue: cell.rawValue,
            newValue: editText.isEmpty ? nil : editText
        )
        appState.pendingEdits.append(edit)
    }
}

// MARK: - Empty & Loading

struct EmptyDataView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: GlintDesign.spacingMD) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.quaternary)

            Text(appState.hasActiveFilters ? "No matching rows" : "Table is empty")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            if appState.hasActiveFilters {
                Button("Clear Filters") {
                    Task { await appState.clearAllFilters() }
                }
                .buttonStyle(GlintButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: GlintDesign.spacingSM) {
            ProgressView()
                .controlSize(.regular)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
