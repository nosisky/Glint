import SwiftUI

/// Data grid — fills full width and height, columns auto-sized, content pinned to top.
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

                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        // Header
                        HeaderView(columns: columns, widths: widths)

                        // Data rows
                        ForEach(Array(appState.queryResult.rows.enumerated()), id: \.element.id) { index, row in
                            RowView(row: row, widths: widths, index: index)
                        }

                        // Empty grid lines — fill remaining space like Postico
                        let rowsDrawn = appState.queryResult.rows.count
                        let rowHeight: CGFloat = 22
                        let headerHeight: CGFloat = 24
                        let usedHeight = headerHeight + CGFloat(rowsDrawn) * rowHeight
                        let remaining = max(0, geo.size.height - usedHeight)
                        let emptyRowCount = Int(remaining / rowHeight) + 1

                        ForEach(0..<emptyRowCount, id: \.self) { i in
                            EmptyRowView(widths: widths, index: rowsDrawn + i)
                        }
                    }
                    .frame(minWidth: totalWidth)
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
            if col.isBoolean { return 70 }
            if col.isNumeric { return 90 }
            if col.isTemporal { return 160 }
            let nameWidth = max(CGFloat(col.name.count) * 8, 100)
            return min(nameWidth, 240)
        }

        let totalMin = minWidths.reduce(0, +)

        if totalMin >= usable {
            return minWidths
        }

        let extra = usable - totalMin
        let perColumn = extra / CGFloat(columns.count)
        return minWidths.map { $0 + perColumn }
    }
}

// MARK: - Header

private struct HeaderView: View {
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
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .frame(height: 24)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }
}

// MARK: - Data Row

private struct RowView: View {
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
                        .fill(Color(nsColor: .separatorColor).opacity(0.3))
                        .frame(width: 1)
                }
            }
        }
        .frame(height: 22)
        .background {
            if isHovered {
                Color.accentColor.opacity(0.08)
            } else if index % 2 == 1 {
                Color(nsColor: .alternatingContentBackgroundColors[1])
            }
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Empty Row (grid lines extending past data, like Postico)

private struct EmptyRowView: View {
    let widths: [CGFloat]
    let index: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { i, w in
                Color.clear
                    .frame(width: w)

                if i < widths.count - 1 {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.15))
                        .frame(width: 1)
                }
            }
        }
        .frame(height: 22)
        .background {
            if index % 2 == 1 {
                Color(nsColor: .alternatingContentBackgroundColors[1])
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
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .onSubmit { commitEdit() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(cell.displayValue)
                    .font(.system(size: 11, design: cell.isNull ? .default : .monospaced))
                    .foregroundStyle(cell.isNull ? .tertiary : .primary)
                    .italic(cell.isNull)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
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

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
