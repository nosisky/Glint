import SwiftUI

/// Data grid — Postico-style: pinned header, horizontally synced scrolling,
/// columns fill width, empty grid rows extend downward.
struct DataGridView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.isLoadingData && appState.queryResult.rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.queryResult.rows.isEmpty && !appState.isLoadingData {
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
            GeometryReader { geo in
                let columns = appState.queryResult.columns
                let widths = calculateColumnWidths(columns: columns, available: geo.size.width)
                let totalWidth = widths.reduce(0, +) + CGFloat(max(columns.count - 1, 0))
                let viewHeight = geo.size.height

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // Pinned header (only scrolls horizontally, not vertically)
                        GridHeader(columns: columns, widths: widths)

                        // Vertical scroll for rows
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 0) {
                                // Data rows
                                ForEach(Array(appState.queryResult.rows.enumerated()), id: \.element.id) { index, row in
                                    GridRow(row: row, widths: widths, index: index)
                                }

                                // Empty rows fill remaining space
                                let rowsDrawn = appState.queryResult.rows.count
                                let usedHeight = CGFloat(rowsDrawn) * 24
                                let headerH: CGFloat = 24
                                let remaining = max(0, viewHeight - headerH - usedHeight)
                                let emptyCount = Int(remaining / 24) + 1

                                ForEach(0..<emptyCount, id: \.self) { i in
                                    EmptyGridRow(widths: widths, index: rowsDrawn + i)
                                }
                            }
                        }
                    }
                    .frame(minWidth: max(totalWidth, geo.size.width))
                }
                .overlay(alignment: .topTrailing) {
                    if appState.isLoadingData {
                        ProgressView()
                            .controlSize(.small)
                            .padding(6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }
            }
        }
    }

    private func calculateColumnWidths(columns: [ColumnInfo], available: CGFloat) -> [CGFloat] {
        guard !columns.isEmpty else { return [] }

        let separators = CGFloat(max(columns.count - 1, 0))
        let usable = available - separators

        let minWidths: [CGFloat] = columns.map { col in
            if col.isBoolean { return 80 }
            if col.isNumeric { return 100 }
            if col.isTemporal { return 180 }
            let nameWidth = max(CGFloat(col.name.count) * 8 + 16, 100)
            return min(nameWidth, 260)
        }

        let totalMin = minWidths.reduce(0, +)
        if totalMin >= usable { return minWidths }

        let extra = usable - totalMin
        let perColumn = extra / CGFloat(columns.count)
        return minWidths.map { $0 + perColumn }
    }
}

// MARK: - Grid Header

private struct GridHeader: View {
    let columns: [ColumnInfo]
    let widths: [CGFloat]
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { i, col in
                Button {
                    Task { await appState.toggleSort(column: col.name) }
                } label: {
                    HStack(spacing: 3) {
                        Text(col.name)
                            .lineLimit(1)

                        if appState.orderByColumn == col.name {
                            Image(systemName: appState.orderAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()
                    }
                    .frame(width: widths[safe: i] ?? 120)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)

                if i < columns.count - 1 {
                    Divider().frame(height: 16)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }
}

// MARK: - Data Row

private struct GridRow: View {
    let row: TableRow
    let widths: [CGFloat]
    let index: Int
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(row.values.enumerated()), id: \.offset) { i, cell in
                CellView(cell: cell, rowId: row.id, columnIndex: i, width: widths[safe: i] ?? 120)

                if i < row.values.count - 1 {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.2))
                        .frame(width: 1)
                }
            }
        }
        .frame(height: 24)
        .background {
            if isHovered {
                Color.accentColor.opacity(0.06)
            } else if index % 2 == 0 {
                Color(nsColor: .controlBackgroundColor).opacity(0.4)
            }
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Empty Row (extends grid lines past data like Postico)

private struct EmptyGridRow: View {
    let widths: [CGFloat]
    let index: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { i, w in
                Color.clear.frame(width: w)

                if i < widths.count - 1 {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.1))
                        .frame(width: 1)
                }
            }
        }
        .frame(height: 24)
        .background {
            if index % 2 == 0 {
                Color(nsColor: .controlBackgroundColor).opacity(0.4)
            }
        }
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
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .onSubmit { commitEdit() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(cell.displayValue)
                    .font(.system(size: 12, design: cell.isNull ? .default : .monospaced))
                    .foregroundStyle(cell.isNull ? Color(nsColor: .tertiaryLabelColor) : .primary)
                    .italic(cell.isNull)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .frame(width: width, height: 24, alignment: .leading)
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

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
