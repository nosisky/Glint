import SwiftUI
import AppKit

struct DataGridView: NSViewRepresentable {
    @Environment(AppState.self) var appState

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = GlintTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = [.solidVerticalGridLineMask]
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.15)
        tableView.headerView = NSTableHeaderView()
        tableView.cornerView = nil
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        let coord = context.coordinator

        let columns = appState.queryResult.columns
        let rows = appState.queryResult.rows

        var enrichedMap: [String: ColumnInfo] = [:]
        if let table = appState.selectedTable {
            for col in table.columns { enrichedMap[col.name] = col }
        }

        let columnIds = columns.map(\.name)
        if coord.lastColumnIds != columnIds {
            rebuildColumns(tableView: tableView, columns: columns, enriched: enrichedMap)
            coord.lastColumnIds = columnIds
            coord.needsInitialSizing = true
        }

        coord.columns = columns
        coord.enrichedColumns = enrichedMap
        coord.appState = appState
        tableView.delegate = coord
        tableView.dataSource = coord

        let dataFingerprint = "\(rows.count)-\(rows.first?.id.uuidString ?? "")-\(rows.last?.id.uuidString ?? "")-\(appState.pendingEdits.count)"
        if coord.lastDataFingerprint != dataFingerprint {
            coord.rows = rows
            coord.pendingEditKeys = Set(appState.pendingEdits.map { "\($0.rowId)-\($0.columnIndex)" })
            tableView.reloadData()
            coord.lastDataFingerprint = dataFingerprint
        }

        if coord.needsInitialSizing && !rows.isEmpty {
            autoSizeColumns(tableView: tableView, columns: columns, rows: rows)
            coord.needsInitialSizing = false
        }
    }

    func makeCoordinator() -> GridCoordinator {
        GridCoordinator()
    }

    // MARK: - Column Setup

    private func rebuildColumns(tableView: NSTableView, columns: [ColumnInfo], enriched: [String: ColumnInfo]) {
        for col in tableView.tableColumns.reversed() { tableView.removeTableColumn(col) }

        for colInfo in columns {
            let meta = enriched[colInfo.name] ?? colInfo
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(colInfo.name))
            col.title = colInfo.name
            col.headerToolTip = columnTooltip(meta)
            col.sortDescriptorPrototype = NSSortDescriptor(key: colInfo.name, ascending: true)
            col.resizingMask = .userResizingMask
            col.minWidth = 60
            col.maxWidth = 600

            if meta.isBoolean { col.width = 80 }
            else if meta.isNumeric { col.width = 100 }
            else if meta.isTemporal { col.width = 200 }
            else { col.width = max(CGFloat(colInfo.name.count) * 8 + 24, 140) }

            tableView.addTableColumn(col)
        }
    }

    private func autoSizeColumns(tableView: NSTableView, columns: [ColumnInfo], rows: [TableRow]) {
        for (i, col) in tableView.tableColumns.enumerated() where i < columns.count {
            let headerWidth = CGFloat(columns[i].name.count) * 8 + 24
            var maxDataWidth: CGFloat = 0
            for row in rows.prefix(50) where i < row.values.count {
                let w = CGFloat(row.values[i].displayValue.count) * 7.5 + 16
                maxDataWidth = max(maxDataWidth, w)
            }
            col.width = max(headerWidth, min(maxDataWidth, 400))
        }
    }

    private func columnTooltip(_ col: ColumnInfo) -> String {
        var parts = [col.typeLabel]
        if !col.isNullable { parts.append("NOT NULL") }
        if col.isPrimaryKey { parts.append("PK") }
        if let fk = col.foreignKey { parts.append("→ \(fk.referencedTable).\(fk.referencedColumn)") }
        if let vals = col.enumValues { parts.append("[\(vals.joined(separator: ", "))]") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Coordinator

@MainActor
final class GridCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    weak var tableView: NSTableView?
    var columns: [ColumnInfo] = []
    var enrichedColumns: [String: ColumnInfo] = [:]
    var rows: [TableRow] = []
    weak var appState: AppState?
    var lastColumnIds: [String] = []
    var lastDataFingerprint = ""
    var pendingEditKeys: Set<String> = []
    var needsInitialSizing = true

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn,
              let colIndex = tableView.tableColumns.firstIndex(of: tableColumn),
              row < rows.count,
              colIndex < rows[row].values.count
        else { return nil }

        let cell = rows[row].values[colIndex]
        let colName = tableColumn.identifier.rawValue
        let meta = enrichedColumns[colName]
        let pending = hasPendingEdit(row: row, col: colIndex)

        if meta?.isBoolean == true {
            return CellFactory.boolean(cell: cell, row: row, col: colIndex, pending: pending, delegate: self)
        }
        if let enumValues = meta?.enumValues, !enumValues.isEmpty {
            return CellFactory.enumPicker(cell: cell, row: row, col: colIndex, values: enumValues, pending: pending, delegate: self)
        }
        if let fk = meta?.foreignKey {
            return CellFactory.foreignKey(cell: cell, row: row, col: colIndex, fk: fk, pending: pending, delegate: self)
        }

        let reuseId = NSUserInterfaceItemIdentifier("TextCell")
        if let reused = tableView.makeView(withIdentifier: reuseId, owner: nil) as? NSTableCellView,
           let field = reused.textField {
            field.stringValue = cell.displayValue
            field.font = cell.isNull ? .systemFont(ofSize: 12) : .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.textColor = cell.isNull ? .tertiaryLabelColor : .labelColor
            field.tag = CellFactory.encodeTag(row: row, col: colIndex)
            field.delegate = self
            reused.wantsLayer = true
            reused.layer?.backgroundColor = pending ? NSColor.systemYellow.withAlphaComponent(0.12).cgColor : nil
            return reused
        }

        let view = CellFactory.text(cell: cell, row: row, col: colIndex, pending: pending, delegate: self)
        view.identifier = reuseId
        return view
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let key = tableView.sortDescriptors.first?.key else { return }
        Task { [weak self] in await self?.appState?.toggleSort(column: key) }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        let (row, col) = CellFactory.decodeTag(textField.tag)
        guard row < rows.count, col < rows[row].values.count else { return }

        let cell = rows[row].values[col]
        let newValue = textField.stringValue
        guard newValue != (cell.rawValue ?? "") else { return }

        recordEdit(row: row, col: col, cell: cell, newValue: newValue.isEmpty ? nil : newValue)
    }

    // MARK: - Actions

    @objc func popupChanged(_ sender: NSPopUpButton) {
        let (row, col) = CellFactory.decodeTag(sender.tag)
        guard row < rows.count, col < rows[row].values.count else { return }

        let cell = rows[row].values[col]
        let newValue = sender.titleOfSelectedItem ?? ""
        guard newValue != (cell.rawValue ?? "") else { return }

        recordEdit(row: row, col: col, cell: cell, newValue: newValue)
    }

    @objc func fkLinkClicked(_ sender: NSButton) {
        let (row, col) = CellFactory.decodeTag(sender.tag)
        guard row < rows.count, col < rows[row].values.count else { return }

        let cell = rows[row].values[col]
        guard let fk = enrichedColumns[cell.columnName]?.foreignKey,
              let value = cell.rawValue,
              let appState else { return }

        Task {
            for schema in appState.schemas {
                if let refTable = schema.tables.first(where: { $0.name == fk.referencedTable }) {
                    await appState.selectTable(refTable)
                    await appState.addFilter(FilterConstraint(
                        columnName: fk.referencedColumn,
                        columnType: "text",
                        operation: .equals,
                        value: .text(value)
                    ))
                    return
                }
            }
        }
    }

    // MARK: - Helpers

    private func hasPendingEdit(row: Int, col: Int) -> Bool {
        guard row < rows.count else { return false }
        return pendingEditKeys.contains("\(rows[row].id)-\(col)")
    }

    private func recordEdit(row: Int, col: Int, cell: CellValue, newValue: String?) {
        guard let appState else { return }
        let rowId = rows[row].id

        appState.pendingEdits.removeAll { $0.rowId == rowId && $0.columnIndex == col }

        if newValue != cell.rawValue {
            appState.pendingEdits.append(PendingEdit(
                rowId: rowId,
                columnIndex: col,
                columnName: cell.columnName,
                originalValue: cell.rawValue,
                newValue: newValue
            ))
        }
    }
}

// MARK: - Cell Factory

@MainActor
enum CellFactory {
    static func encodeTag(row: Int, col: Int) -> Int { row * 10000 + col }
    static func decodeTag(_ tag: Int) -> (row: Int, col: Int) { (tag / 10000, tag % 10000) }

    static func text(cell: CellValue, row: Int, col: Int, pending: Bool, delegate: NSTextFieldDelegate) -> NSView {
        let view = NSTableCellView()
        let field = editableTextField(cell: cell, row: row, col: col, delegate: delegate)
        view.addSubview(field)
        view.textField = field
        pinTextField(field, in: view)
        applyPendingStyle(view, pending: pending)
        return view
    }

    static func boolean(cell: CellValue, row: Int, col: Int, pending: Bool, delegate: GridCoordinator) -> NSView {
        let view = NSView()
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        popup.isBordered = false
        popup.addItems(withTitles: ["TRUE", "FALSE"])
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.tag = encodeTag(row: row, col: col)
        popup.target = delegate
        popup.action = #selector(GridCoordinator.popupChanged(_:))

        let current = cell.rawValue?.lowercased()
        popup.selectItem(at: (current == "true" || current == "t") ? 0 : 1)

        view.addSubview(popup)
        pinPopup(popup, in: view)
        applyPendingStyle(view, pending: pending)
        return view
    }

    static func enumPicker(cell: CellValue, row: Int, col: Int, values: [String], pending: Bool, delegate: GridCoordinator) -> NSView {
        let view = NSView()
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        popup.isBordered = false
        popup.addItems(withTitles: values)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.tag = encodeTag(row: row, col: col)
        popup.target = delegate
        popup.action = #selector(GridCoordinator.popupChanged(_:))

        if let current = cell.rawValue { popup.selectItem(withTitle: current) }

        view.addSubview(popup)
        pinPopup(popup, in: view)
        applyPendingStyle(view, pending: pending)
        return view
    }

    static func foreignKey(cell: CellValue, row: Int, col: Int, fk: ForeignKeyRef, pending: Bool, delegate: GridCoordinator) -> NSView {
        let view = NSView()

        let field = editableTextField(cell: cell, row: row, col: col, delegate: delegate)
        view.addSubview(field)

        let link = NSButton(title: "", target: delegate, action: #selector(GridCoordinator.fkLinkClicked(_:)))
        link.image = NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: nil)
        link.imageScaling = .scaleProportionallyDown
        link.isBordered = false
        link.bezelStyle = .inline
        link.contentTintColor = .systemBlue
        link.tag = encodeTag(row: row, col: col)
        link.toolTip = "→ \(fk.referencedTable).\(fk.referencedColumn)"
        link.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(link)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: link.leadingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            link.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            link.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            link.widthAnchor.constraint(equalToConstant: 16),
            link.heightAnchor.constraint(equalToConstant: 16),
        ])

        applyPendingStyle(view, pending: pending)
        return view
    }

    // MARK: - Shared Components

    private static func editableTextField(cell: CellValue, row: Int, col: Int, delegate: NSTextFieldDelegate) -> NSTextField {
        let field = NSTextField()
        field.stringValue = cell.displayValue
        field.isEditable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingMiddle
        field.font = cell.isNull ? .systemFont(ofSize: 12) : .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = cell.isNull ? .tertiaryLabelColor : .labelColor
        field.delegate = delegate
        field.tag = encodeTag(row: row, col: col)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private static func pinTextField(_ field: NSTextField, in parent: NSView) {
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
        ])
    }

    private static func pinPopup(_ popup: NSPopUpButton, in parent: NSView) {
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 2),
            popup.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -2),
            popup.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
        ])
    }

    private static func applyPendingStyle(_ view: NSView, pending: Bool) {
        guard pending else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.12).cgColor
    }
}

// MARK: - Table View Subclass

private class GlintTableView: NSTableView {
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        true
    }
}
