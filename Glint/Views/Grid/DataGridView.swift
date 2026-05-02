//
//  DataGridView.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI
import AppKit

struct DataGridView: NSViewRepresentable {
    @Environment(AppState.self) var appState
    
    var customResult: QueryResult?
    var customTable: TableInfo?
    var isPickerMode: Bool = false
    var initialSelection: String?
    var onRowPicked: ((TableRow) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = GlintTableView()
        tableView.coordinator = context.coordinator
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.rowHeight = 26
        tableView.intercellSpacing = NSSize(width: 8, height: 4)
        tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.08)
        tableView.headerView = NSTableHeaderView()
        tableView.cornerView = nil
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .regular

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        let coord = context.coordinator

        let columns = customResult?.columns ?? appState.queryResult.columns
        let rows = customResult?.rows ?? appState.queryResult.rows

        var enrichedMap: [String: ColumnInfo] = [:]
        if let table = customTable ?? appState.selectedTable {
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
        coord.isPickerMode = isPickerMode
        coord.initialSelection = initialSelection
        coord.onRowPicked = onRowPicked
        tableView.delegate = coord
        tableView.dataSource = coord

        if isPickerMode {
            tableView.target = coord
            tableView.doubleAction = #selector(GridCoordinator.rowDoubleClicked(_:))
            tableView.allowsMultipleSelection = false
        } else {
            tableView.target = nil
            tableView.doubleAction = nil
            tableView.allowsMultipleSelection = true
        }

        let pendingCount = isPickerMode ? 0 : appState.pendingEdits.count
        let dataFingerprint = "\(rows.count)-\(rows.first?.id.uuidString ?? "")-\(rows.last?.id.uuidString ?? "")-\(pendingCount)"
        if coord.lastDataFingerprint != dataFingerprint {
            coord.rows = rows
            coord.pendingEditKeys = isPickerMode ? [] : Set(appState.pendingEdits.map { "\($0.rowId)-\($0.columnIndex)" })
            tableView.reloadData()
            coord.lastDataFingerprint = dataFingerprint
            
            if isPickerMode && !coord.hasScrolledToInitialSelection, let target = coord.initialSelection {
                if let idx = rows.firstIndex(where: { $0.values.contains(where: { $0.rawValue == target }) }) {
                    tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                    DispatchQueue.main.async { tableView.scrollRowToVisible(idx) }
                }
                coord.hasScrolledToInitialSelection = true
            }
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
    var currentPopover: NSPopover?
    var isPickerMode: Bool = false
    var initialSelection: String?
    var hasScrolledToInitialSelection = false
    var onRowPicked: ((TableRow) -> Void)?

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

        if !isPickerMode {
            if meta?.isBoolean == true {
                return CellFactory.boolean(cell: cell, row: row, col: colIndex, pending: pending, delegate: self)
            }
            if let enumValues = meta?.enumValues, !enumValues.isEmpty {
                return CellFactory.enumPicker(cell: cell, row: row, col: colIndex, values: enumValues, pending: pending, delegate: self)
            }
            if cell.dataType == "json" || cell.dataType == "jsonb" {
                return CellFactory.jsonViewer(cell: cell, row: row, col: colIndex, pending: pending, delegate: self)
            }
            if let fk = meta?.foreignKey {
                return CellFactory.foreignKey(cell: cell, row: row, col: colIndex, fk: fk, pending: pending, delegate: self)
            }
        }

        let reuseId = NSUserInterfaceItemIdentifier("TextCell\(isPickerMode ? "Picker" : "")")
        if let reused = tableView.makeView(withIdentifier: reuseId, owner: nil) as? NSTableCellView,
           let field = reused.textField {
            field.stringValue = cell.displayValue
            field.font = cell.isNull ? .systemFont(ofSize: 12) : .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.textColor = cell.isNull ? .tertiaryLabelColor : .labelColor
            field.tag = CellFactory.encodeTag(row: row, col: colIndex)
            field.isEditable = !isPickerMode
            field.delegate = self
            reused.wantsLayer = true
            reused.layer?.backgroundColor = pending ? NSColor.systemYellow.withAlphaComponent(0.12).cgColor : nil
            return reused
        }

        let view = CellFactory.text(cell: cell, row: row, col: colIndex, pending: pending, delegate: self)
        view.identifier = reuseId
        if isPickerMode {
            view.subviews.compactMap { $0 as? NSTextField }.first?.isEditable = false
        }
        return view
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let key = tableView.sortDescriptors.first?.key else { return }
        Task { [weak self] in await self?.appState?.toggleSort(column: key) }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView, let appState else { return }
        let selectedIndexes = tableView.selectedRowIndexes
        var selectedIds = Set<UUID>()
        for idx in selectedIndexes {
            if idx < rows.count {
                selectedIds.insert(rows[idx].id)
            }
        }
        appState.selectedRowIds = selectedIds
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField,
              let tableView = self.tableView else { return }
        let (row, _) = CellFactory.decodeTag(textField.tag)
        if !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

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

    @objc func rowDoubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0 && row < rows.count else { return }
        onRowPicked?(rows[row])
    }

    @objc func duplicateRow(_ sender: NSMenuItem) {
        guard let appState = appState else { return }
        let row = sender.tag
        Task { await appState.duplicateRow(at: row) }
    }

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
              let appState = self.appState else { return }

        guard let refTable = appState.schemas.lazy.flatMap({ $0.tables }).first(where: { $0.name == fk.referencedTable }) else {
            return
        }

        let rowId = rows[row].id
        
        currentPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        self.currentPopover = popover
        
        let popoverView = ForeignKeyPreviewPopover(
            table: refTable,
            referencedColumn: fk.referencedColumn,
            value: value,
            onClose: { [weak popover] in popover?.close() },
            onPick: { [weak appState, weak popover] pickedValue in
                guard let appState else { return }
                appState.pendingEdits.removeAll { $0.rowId == rowId && $0.columnIndex == col }
                if pickedValue != cell.rawValue {
                    appState.pendingEdits.append(PendingEdit(
                        rowId: rowId,
                        columnIndex: col,
                        columnName: cell.columnName,
                        originalValue: cell.rawValue,
                        newValue: pickedValue
                    ))
                }
                popover?.close()
            }
        ).environment(appState)
        
        popover.contentViewController = NSHostingController(rootView: popoverView)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    @objc func jsonLinkClicked(_ sender: NSButton) {
        openJSONEditor(tag: sender.tag, sourceView: sender)
    }

    @objc func jsonFieldDoubleClicked(_ gesture: NSClickGestureRecognizer) {
        guard let view = gesture.view else { return }
        openJSONEditor(tag: view.tag, sourceView: view)
    }

    private func openJSONEditor(tag: Int, sourceView: NSView) {
        let (row, col) = CellFactory.decodeTag(tag)
        guard row < rows.count, col < rows[row].values.count else { return }

        let cell = rows[row].values[col]
        guard let appState = self.appState else { return }

        let rowId = rows[row].id
        
        currentPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        self.currentPopover = popover
        
        let popoverView = JSONEditorPopover(
            columnName: cell.columnName,
            initialValue: cell.rawValue,
            onClose: { [weak popover] in popover?.close() },
            onSave: { [weak appState, weak popover] pickedValue in
                guard let appState else { return }
                appState.pendingEdits.removeAll { $0.rowId == rowId && $0.columnIndex == col }
                if pickedValue != cell.rawValue {
                    appState.pendingEdits.append(PendingEdit(
                        rowId: rowId,
                        columnIndex: col,
                        columnName: cell.columnName,
                        originalValue: cell.rawValue,
                        newValue: pickedValue
                    ))
                }
                popover?.close()
            }
        ).environment(appState)
        
        popover.contentViewController = NSHostingController(rootView: popoverView)
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .minY)
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
    static func encodeTag(row: Int, col: Int) -> Int { row * 100_000 + col }
    static func decodeTag(_ tag: Int) -> (row: Int, col: Int) { (tag / 100_000, tag % 100_000) }

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
        popup.font = .systemFont(ofSize: 12, weight: .regular)
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
        popup.font = .systemFont(ofSize: 12, weight: .regular)
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

        let link = NSButton(title: "", target: delegate, action: #selector(GridCoordinator.fkLinkClicked(_:)))
        link.image = NSImage(systemSymbolName: "tablecells.fill", accessibilityDescription: nil)
        link.imageScaling = .scaleProportionallyDown
        link.isBordered = false
        link.bezelStyle = .inline
        link.contentTintColor = NSColor.tertiaryLabelColor // Subtle, hover will highlight natively
        link.tag = encodeTag(row: row, col: col)
        link.toolTip = "Preview → \(fk.referencedTable).\(fk.referencedColumn)"
        link.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(link)

        let field = editableTextField(cell: cell, row: row, col: col, delegate: delegate)
        view.addSubview(field)

        NSLayoutConstraint.activate([
            link.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            link.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            link.widthAnchor.constraint(equalToConstant: 14),
            link.heightAnchor.constraint(equalToConstant: 14),
            
              field.leadingAnchor.constraint(equalTo: link.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        applyPendingStyle(view, pending: pending)
        return view
    }

    static func jsonViewer(cell: CellValue, row: Int, col: Int, pending: Bool, delegate: GridCoordinator) -> NSView {
        let view = NSView()

        let link = NSButton(title: "", target: delegate, action: #selector(GridCoordinator.jsonLinkClicked(_:)))
        link.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
        link.imageScaling = .scaleProportionallyDown
        link.isBordered = false
        link.bezelStyle = .inline
        link.contentTintColor = NSColor.tertiaryLabelColor
        link.tag = encodeTag(row: row, col: col)
        link.toolTip = "Edit JSON"
        link.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(link)

        let field = editableTextField(cell: cell, row: row, col: col, delegate: delegate)
        field.isEditable = false // Disable inline edit for JSON
        field.tag = encodeTag(row: row, col: col)
        
        let click = NSClickGestureRecognizer(target: delegate, action: #selector(GridCoordinator.jsonFieldDoubleClicked(_:)))
        click.numberOfClicksRequired = 2
        field.addGestureRecognizer(click)
        
        view.addSubview(field)

        NSLayoutConstraint.activate([
            link.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            link.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            link.widthAnchor.constraint(equalToConstant: 14),
            link.heightAnchor.constraint(equalToConstant: 14),
            
            field.leadingAnchor.constraint(equalTo: link.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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
        field.lineBreakMode = .byTruncatingTail
        // Use a modern, readable proportional font for data instead of monospaced
        field.font = cell.isNull ? .systemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 13, weight: .regular)
        field.textColor = cell.isNull ? .tertiaryLabelColor : .labelColor
        field.delegate = delegate
        field.tag = encodeTag(row: row, col: col)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private static func pinTextField(_ field: NSTextField, in parent: NSView) {
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -8),
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
    weak var coordinator: GridCoordinator?

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return super.menu(for: event) }
        
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        
        let menu = NSMenu()
        let dupItem = NSMenuItem(title: "Duplicate Row", action: #selector(GridCoordinator.duplicateRow(_:)), keyEquivalent: "")
        dupItem.target = coordinator
        dupItem.tag = row
        menu.addItem(dupItem)
        return menu
    }
}
