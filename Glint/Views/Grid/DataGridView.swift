import SwiftUI
import AppKit

/// NSTableView-backed data grid with inline editing, enum pickers, and FK popovers.
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

        // Build enriched column map from selectedTable (has enum/FK info)
        var enrichedMap: [String: ColumnInfo] = [:]
        if let table = appState.selectedTable {
            for col in table.columns {
                enrichedMap[col.name] = col
            }
        }

        // Update columns if changed
        if coordinator.lastColumnIds != columns.map(\.name) {
            for col in tableView.tableColumns.reversed() {
                tableView.removeTableColumn(col)
            }

            for colInfo in columns {
                let enriched = enrichedMap[colInfo.name] ?? colInfo
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(colInfo.name))
                col.title = colInfo.name

                // Tooltip shows type + constraints
                var tooltip = enriched.typeLabel
                if !enriched.isNullable { tooltip += " NOT NULL" }
                if enriched.isPrimaryKey { tooltip += " PRIMARY KEY" }
                if let fk = enriched.foreignKey { tooltip += " → \(fk.referencedTable).\(fk.referencedColumn)" }
                col.headerToolTip = tooltip

                // Width
                let nameWidth = max(CGFloat(colInfo.name.count) * 8 + 24, 80)
                if enriched.isBoolean { col.width = 80; col.minWidth = 60 }
                else if enriched.isNumeric { col.width = 100; col.minWidth = 60 }
                else if enriched.isTemporal { col.width = 200; col.minWidth = 120 }
                else { col.width = max(nameWidth, 140); col.minWidth = 80 }
                col.maxWidth = 600
                col.resizingMask = .userResizingMask

                col.sortDescriptorPrototype = NSSortDescriptor(key: colInfo.name, ascending: true)
                tableView.addTableColumn(col)
            }

            coordinator.lastColumnIds = columns.map(\.name)
            coordinator.needsInitialSizing = true
        }

        // Update data
        coordinator.columns = columns
        coordinator.enrichedColumns = enrichedMap
        coordinator.rows = rows
        coordinator.appState = appState
        tableView.delegate = coordinator
        tableView.dataSource = coordinator
        tableView.reloadData()

        // Auto-resize columns to fit content
        if coordinator.needsInitialSizing && !rows.isEmpty {
            for (i, col) in tableView.tableColumns.enumerated() {
                guard i < columns.count else { continue }
                let headerWidth = CGFloat(columns[i].name.count) * 8 + 24
                var maxDataWidth: CGFloat = 0
                for row in rows.prefix(50) {
                    if i < row.values.count {
                        let cellWidth = CGFloat(row.values[i].displayValue.count) * 7.5 + 16
                        maxDataWidth = max(maxDataWidth, cellWidth)
                    }
                }
                col.width = max(headerWidth, min(maxDataWidth, 400))
            }
            coordinator.needsInitialSizing = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    @MainActor class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var tableView: NSTableView?
        var scrollView: NSScrollView?
        var columns: [ColumnInfo] = []
        var enrichedColumns: [String: ColumnInfo] = [:]
        var rows: [TableRow] = []
        var appState: AppState?
        var lastColumnIds: [String] = []
        var needsInitialSizing = true

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
            let colName = tableColumn.identifier.rawValue
            let enriched = enrichedColumns[colName]
            let pending = isPending(row: row, col: colIndex)

            // Boolean column → popup button (TRUE/FALSE)
            if enriched?.isBoolean == true {
                return makeBooleanCell(cell: cell, row: row, colIndex: colIndex, pending: pending)
            }

            // Enum column → popup button with values
            if let enumValues = enriched?.enumValues, !enumValues.isEmpty {
                return makeEnumCell(cell: cell, row: row, colIndex: colIndex, enumValues: enumValues, pending: pending)
            }

            // FK column → text + link button
            if let fk = enriched?.foreignKey {
                return makeFKCell(cell: cell, row: row, colIndex: colIndex, fk: fk, pending: pending)
            }

            // Regular text cell → editable on double-click
            return makeTextCell(cell: cell, row: row, colIndex: colIndex, pending: pending)
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key else { return }
            Task { [weak self] in
                await self?.appState?.toggleSort(column: key)
            }
        }

        // MARK: - Text Field Delegate (inline editing)

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField,
                  let appState else { return }

            let row = textField.tag / 10000
            let col = textField.tag % 10000
            let newValue = textField.stringValue

            guard row < rows.count, col < rows[row].values.count else { return }
            let cell = rows[row].values[col]
            let originalValue = cell.rawValue

            guard newValue != (originalValue ?? "") else { return }

            appState.pendingEdits.append(PendingEdit(
                rowId: rows[row].id,
                columnIndex: col,
                columnName: cell.columnName,
                originalValue: originalValue,
                newValue: newValue.isEmpty ? nil : newValue
            ))
        }

        // MARK: - Cell Factories

        private func makeTextCell(cell: CellValue, row: Int, colIndex: Int, pending: Bool) -> NSView {
            let cellView = NSTableCellView()
            let textField = NSTextField()
            textField.stringValue = cell.displayValue
            textField.isEditable = true
            textField.isBordered = false
            textField.drawsBackground = false
            textField.font = cell.isNull ? .systemFont(ofSize: 12) : .monospacedSystemFont(ofSize: 12, weight: .regular)
            textField.textColor = cell.isNull ? .tertiaryLabelColor : .labelColor
            textField.lineBreakMode = .byTruncatingMiddle
            textField.focusRingType = .none
            textField.delegate = self
            textField.tag = row * 10000 + colIndex
            textField.translatesAutoresizingMaskIntoConstraints = false

            cellView.addSubview(textField)
            cellView.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])

            applyPendingHighlight(cellView, pending: pending)
            return cellView
        }

        private func makeBooleanCell(cell: CellValue, row: Int, colIndex: Int, pending: Bool) -> NSView {
            let cellView = NSView()
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            popup.isBordered = false
            popup.addItems(withTitles: ["TRUE", "FALSE"])

            // Select current value
            let current = cell.rawValue?.lowercased()
            if current == "true" || current == "t" {
                popup.selectItem(at: 0)
            } else {
                popup.selectItem(at: 1)
            }

            popup.tag = row * 10000 + colIndex
            popup.target = self
            popup.action = #selector(booleanChanged(_:))
            popup.translatesAutoresizingMaskIntoConstraints = false

            cellView.addSubview(popup)
            NSLayoutConstraint.activate([
                popup.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                popup.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -2),
                popup.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])

            applyPendingHighlight(cellView, pending: pending)
            return cellView
        }

        private func makeEnumCell(cell: CellValue, row: Int, colIndex: Int, enumValues: [String], pending: Bool) -> NSView {
            let cellView = NSView()
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            popup.isBordered = false
            popup.addItems(withTitles: enumValues)

            if let current = cell.rawValue {
                popup.selectItem(withTitle: current)
            }

            popup.tag = row * 10000 + colIndex
            popup.target = self
            popup.action = #selector(enumChanged(_:))
            popup.translatesAutoresizingMaskIntoConstraints = false

            cellView.addSubview(popup)
            NSLayoutConstraint.activate([
                popup.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                popup.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -2),
                popup.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])

            applyPendingHighlight(cellView, pending: pending)
            return cellView
        }

        private func makeFKCell(cell: CellValue, row: Int, colIndex: Int, fk: ForeignKeyRef, pending: Bool) -> NSView {
            let cellView = NSView()

            // Text showing the value
            let textField = NSTextField()
            textField.stringValue = cell.displayValue
            textField.isEditable = true
            textField.isBordered = false
            textField.drawsBackground = false
            textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textField.textColor = cell.isNull ? .tertiaryLabelColor : .labelColor
            textField.lineBreakMode = .byTruncatingMiddle
            textField.focusRingType = .none
            textField.delegate = self
            textField.tag = row * 10000 + colIndex
            textField.translatesAutoresizingMaskIntoConstraints = false

            // FK link button
            let linkButton = NSButton(title: "", target: self, action: #selector(fkClicked(_:)))
            linkButton.image = NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: "Open referenced row")
            linkButton.imageScaling = .scaleProportionallyDown
            linkButton.isBordered = false
            linkButton.bezelStyle = .inline
            linkButton.contentTintColor = .systemBlue
            linkButton.tag = row * 10000 + colIndex
            linkButton.toolTip = "→ \(fk.referencedTable).\(fk.referencedColumn)"
            linkButton.translatesAutoresizingMaskIntoConstraints = false

            cellView.addSubview(textField)
            cellView.addSubview(linkButton)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: linkButton.leadingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                linkButton.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                linkButton.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                linkButton.widthAnchor.constraint(equalToConstant: 16),
                linkButton.heightAnchor.constraint(equalToConstant: 16),
            ])

            applyPendingHighlight(cellView, pending: pending)
            return cellView
        }

        // MARK: - Actions

        @objc private func booleanChanged(_ sender: NSPopUpButton) {
            let row = sender.tag / 10000
            let col = sender.tag % 10000
            guard row < rows.count, col < rows[row].values.count else { return }

            let cell = rows[row].values[col]
            let newValue = sender.titleOfSelectedItem ?? "FALSE"
            guard newValue.lowercased() != (cell.rawValue ?? "").lowercased() else { return }

            appState?.pendingEdits.append(PendingEdit(
                rowId: rows[row].id,
                columnIndex: col,
                columnName: cell.columnName,
                originalValue: cell.rawValue,
                newValue: newValue.lowercased()
            ))
        }

        @objc private func enumChanged(_ sender: NSPopUpButton) {
            let row = sender.tag / 10000
            let col = sender.tag % 10000
            guard row < rows.count, col < rows[row].values.count else { return }

            let cell = rows[row].values[col]
            let newValue = sender.titleOfSelectedItem ?? ""
            guard newValue != (cell.rawValue ?? "") else { return }

            appState?.pendingEdits.append(PendingEdit(
                rowId: rows[row].id,
                columnIndex: col,
                columnName: cell.columnName,
                originalValue: cell.rawValue,
                newValue: newValue
            ))
        }

        @objc private func fkClicked(_ sender: NSButton) {
            let row = sender.tag / 10000
            let col = sender.tag % 10000
            guard row < rows.count, col < rows[row].values.count else { return }

            let cell = rows[row].values[col]
            let colName = cell.columnName
            guard let fk = enrichedColumns[colName]?.foreignKey,
                  let value = cell.rawValue,
                  let appState else { return }

            // Navigate to the referenced table and filter by the FK value
            Task {
                for schema in appState.schemas {
                    if let refTable = schema.tables.first(where: { $0.name == fk.referencedTable }) {
                        await appState.selectTable(refTable)
                        // Apply filter for the referenced column = FK value
                        appState.filters = [FilterConstraint(
                            columnName: fk.referencedColumn,
                            columnType: "text",
                            operation: .equals,
                            value: .text(value)
                        )]
                        await appState.fetchTableData()
                        break
                    }
                }
            }
        }

        // MARK: - Helpers

        private func isPending(row: Int, col: Int) -> Bool {
            guard row < rows.count else { return false }
            let rowId = rows[row].id
            return appState?.pendingEdits.contains { $0.rowId == rowId && $0.columnIndex == col } ?? false
        }

        private func applyPendingHighlight(_ view: NSView, pending: Bool) {
            view.wantsLayer = true
            view.layer?.backgroundColor = pending
                ? NSColor.systemYellow.withAlphaComponent(0.12).cgColor
                : nil
        }
    }
}

// MARK: - Custom Header View

private class GlintTableHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}
