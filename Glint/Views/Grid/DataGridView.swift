  import SwiftUI

/// Data grid — compact spreadsheet, Postico-style.
struct DataGridView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isLoadingData && appState.queryResult.rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.queryResult.rows.isEmpty {
                ContentUnavailableView {
                    Label(appState.hasActiveFilters ? "No Results" : "Empty Table", systemImage: "tray")
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
                gridContent
            }
        }
    }

    private var gridContent: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(appState.queryResult.rows.enumerated()), id: \.element.id) { index, row in
                        RowView(row: row, columns: appState.queryResult.columns, index: index)
                    }
                } header: {
                    HeaderView(columns: appState.queryResult.columns)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if appState.isLoadingData {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            }
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    let columns: [ColumnInfo]
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, col in
                Button {
                    Task { await appState.toggleSort(column: col.name) }
                } label: {
                    HStack(spacing: 3) {
                        Text(col.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)

                        if appState.orderByColumn == col.name {
                            Image(systemName: appState.orderAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()
                    }
                    .frame(width: columnWidth(for: col), alignment: .leading)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)

                if index < columns.count - 1 {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                }
            }
        }
        .frame(height: 22)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }

    private func columnWidth(for col: ColumnInfo) -> CGFloat {
        if col.isBoolean { return 80 }
        if col.isNumeric { return 100 }
        return 150
    }
}

// MARK: - Row

private struct RowView: View {
    let row: TableRow
    let columns: [ColumnInfo]
    let index: Int
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(row.values.enumerated()), id: \.offset) { colIndex, cell in
                CellView(
                    cell: cell, rowId: row.id, columnIndex: colIndex,
                    width: columnWidth(colIndex)
                )

                if colIndex < row.values.count - 1 {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.4))
                        .frame(width: 1)
                }
            }
        }
        .frame(height: 20)
        .background {
            if isHovered {
                Color.accentColor.opacity(0.08)
            } else if index % 2 == 1 {
                Color(nsColor: .alternatingContentBackgroundColors[1])
            }
        }
        .onHover { isHovered = $0 }
    }

    private func columnWidth(_ colIndex: Int) -> CGFloat {
        guard colIndex < columns.count else { return 150 }
        let col = columns[colIndex]
        if col.isBoolean { return 80 }
        if col.isNumeric { return 100 }
        return 150
    }
}

// MARK: - Cell

private struct CellView: View {
    let cell: CellValue
    let rowId: UUID
    let columnIndex: Int
    let width: CGFloat
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
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6)
                    .onSubmit { commitEdit() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(cell.displayValue)
                    .font(.system(size: 11, design: cell.isNull ? .default : .monospaced))
                    .foregroundStyle(cell.isNull ? .tertiary : .primary)
                    .italic(cell.isNull)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(width: width, alignment: .leading)
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
