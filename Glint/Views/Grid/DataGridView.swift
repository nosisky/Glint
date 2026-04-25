import SwiftUI
import AppKit

/// NSTableView-backed data grid — guarantees column alignment, header pinning,
/// and horizontal scroll by using native AppKit infrastructure.
struct DataGridView: NSViewRepresentable {
    @Environment(AppState.self) var appState

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
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = [.solidVerticalGridLineMask]
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.2)
        tableView.headerView = GlintTableHeaderView()
        tableView.cornerView = nil
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none

        // Actions
        tableView.doubleAction = #selector(context.coordinator.doubleClickRow(_:))
        tableView.target = context.coordinator

        scrollView.documentView = tableView

        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        let coordinator = context.coordinator

        let columns = appState.queryResult.columns
        let rows = appState.queryResult.rows

        // Update columns if changed
        if coordinator.lastColumnIds != columns.map(\.name) {
            // Remove existing columns
            for col in tableView.tableColumns.reversed() {
                tableView.removeTableColumn(col)
            }

            // Add columns from result
            for colInfo in columns {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(colInfo.name))
                col.title = colInfo.name
                col.headerToolTip = "\(colInfo.udtName)\(colInfo.isNullable ? "" : " NOT NULL")\(colInfo.isPrimaryKey ? " PK" : "")"

                // Width based on column type and name
                let nameWidth = max(CGFloat(colInfo.name.count) * 8 + 24, 80)
                if colInfo.isBoolean {
                    col.width = 80
                    col.minWidth = 60
                } else if colInfo.isNumeric {
                    col.width = 100
                    col.minWidth = 60
                } else if colInfo.isTemporal {
                    col.width = 200
                    col.minWidth = 120
                } else {
                    col.width = max(nameWidth, 140)
                    col.minWidth = 80
                }
                col.maxWidth = 600
                col.resizingMask = .userResizingMask

                // Sort descriptor
                col.sortDescriptorPrototype = NSSortDescriptor(key: colInfo.name, ascending: true)

                tableView.addTableColumn(col)
            }

            coordinator.lastColumnIds = columns.map(\.name)
        }

        // Update data
        coordinator.columns = columns
        coordinator.rows = rows
        coordinator.appState = appState
        tableView.delegate = coordinator
        tableView.dataSource = coordinator
        tableView.reloadData()

        // Auto-resize columns to fit content on first load
        if coordinator.needsInitialSizing && !rows.isEmpty {
            for (i, col) in tableView.tableColumns.enumerated() {
                let headerWidth = CGFloat(columns[i].name.count) * 8 + 24
                var maxDataWidth: CGFloat = 0
                for row in rows.prefix(50) {
                    if i < row.values.count {
                        let cellWidth = CGFloat(row.values[i].displayValue.count) * 7.5 + 16
                        maxDataWidth = max(maxDataWidth, cellWidth)
                    }
                }
                let idealWidth = max(headerWidth, min(maxDataWidth, 400))
                col.width = idealWidth
            }
            coordinator.needsInitialSizing = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var tableView: NSTableView?
        var scrollView: NSScrollView?
        var columns: [ColumnInfo] = []
        var rows: [TableRow] = []
        var appState: AppState?
        var lastColumnIds: [String] = []
        var needsInitialSizing = true
        var editingRowIndex: Int?
        var editingColIndex: Int?

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn,
                  let colIndex = tableView.tableColumns.firstIndex(of: tableColumn),
                  row < rows.count,
                  colIndex < rows[row].values.count
            else { return nil }

            let cell = rows[row].values[colIndex]
            let colInfo = colIndex < columns.count ? columns[colIndex] : nil

            let identifier = NSUserInterfaceItemIdentifier("GlintCell")
            let cellView: GlintCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? GlintCellView {
                cellView = reused
            } else {
                cellView = GlintCellView()
                cellView.identifier = identifier
            }

            cellView.configure(cell: cell, colInfo: colInfo, isPending: isPending(row: row, col: colIndex))
            return cellView
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key else { return }
            Task { [weak self] in
                await self?.appState?.toggleSort(column: key)
            }
        }

        @objc func doubleClickRow(_ sender: NSTableView) {
            let row = sender.clickedRow
            let col = sender.clickedColumn
            guard row >= 0, col >= 0, row < rows.count, col < rows[row].values.count else { return }

            // Start inline editing
            editingRowIndex = row
            editingColIndex = col
            sender.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: col))
        }

        private func isPending(row: Int, col: Int) -> Bool {
            guard row < rows.count else { return false }
            let rowId = rows[row].id
            return appState?.pendingEdits.contains { $0.rowId == rowId && $0.columnIndex == col } ?? false
        }
    }
}

// MARK: - Cell View

private class GlintCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(cell: CellValue, colInfo: ColumnInfo?, isPending: Bool) {
        label.stringValue = cell.displayValue

        if cell.isNull {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .tertiaryLabelColor
        } else {
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.textColor = .labelColor
        }

        // Pending edit highlight
        if isPending {
            wantsLayer = true
            layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.1).cgColor
        } else {
            layer?.backgroundColor = nil
        }
    }
}

// MARK: - Custom Header View (subtle styling)

private class GlintTableHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}
