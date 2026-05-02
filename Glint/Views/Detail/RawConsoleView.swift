//
//  RawConsoleView.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// Opt-in raw SQL console — accessible from the menu (⌘⇧K).
struct RawConsoleView: View {
    @Environment(AppState.self) private var appState
    @State private var sqlText = ""
    @State private var result: ConsoleResult?
    @State private var isExecuting = false
    @State private var showDestructiveConfirmation = false
    @State private var pendingDestructiveSQL = ""
    @State private var destructiveWarning = ""

    enum ConsoleResult {
        case rows(QueryResult)
        case message(String)
        case error(String)
    }

    var body: some View {
        VSplitView {
            // Editor
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if isExecuting { ProgressView().controlSize(.mini) }
                    Button("Execute") { attemptExecution() }
                        .disabled(sqlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExecuting)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                }
                .padding(8)

                TextEditor(text: $sqlText)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
            .frame(minHeight: 80)
            .background(Color(nsColor: .textBackgroundColor))

            // Results
            Group {
                if let result {
                    switch result {
                    case .rows(let queryResult):
                        ConsoleResultsGrid(result: queryResult)
                    case .message(let msg):
                        Label(msg, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    case .error(let err):
                        Label(err, systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 24))
                            .foregroundStyle(.quaternary)
                        Text("⌘⇧↩ to execute")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert("Destructive Query", isPresented: $showDestructiveConfirmation) {
            Button("Execute Anyway", role: .destructive) {
                executeQuery(pendingDestructiveSQL)
            }
            Button("Cancel", role: .cancel) {
                pendingDestructiveSQL = ""
            }
        } message: {
            Text(destructiveWarning + "\n\n" + pendingDestructiveSQL.prefix(500))
        }
    }

    /// Gate: check if the query is destructive before executing.
    private func attemptExecution() {
        let trimmed = sqlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if SQLSanitizer.isDestructive(trimmed) {
            pendingDestructiveSQL = trimmed
            destructiveWarning = SQLSanitizer.destructiveDescription(trimmed)
                ?? "This query may modify data."
            showDestructiveConfirmation = true
        } else {
            executeQuery(trimmed)
        }
    }

    private func executeQuery(_ trimmed: String) {
        guard !trimmed.isEmpty else { return }

        isExecuting = true

        Task {
            guard let pool = appState.connectionPool else {
                result = .error("Not connected.")
                isExecuting = false
                return
            }

            do {
                let conn = try await pool.getConnection()
                let isSelect = trimmed.uppercased().hasPrefix("SELECT")
                    || trimmed.uppercased().hasPrefix("WITH")

                if isSelect {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    let rows = try await conn.queryAll(trimmed)
                    let executionTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

                    var tableRows: [TableRow] = []
                    var columnInfos: [ColumnInfo] = []

                    if let firstRow = rows.first {
                        let cells = firstRow.makeRandomAccess()
                        for i in 0..<cells.count {
                            let cell = cells[i]
                            columnInfos.append(ColumnInfo(
                                name: cell.columnName,
                                tableName: "_console",
                                dataType: cell.dataType.rawValue.description,
                                udtName: cell.dataType.rawValue.description,
                                isNullable: true, isPrimaryKey: false,
                                hasDefault: false, defaultValue: nil,
                                characterMaxLength: nil, numericPrecision: nil,
                                ordinalPosition: i
                            ))
                        }
                    }

                    for row in rows {
                        let ra = row.makeRandomAccess()
                        var values: [CellValue] = []
                        for i in 0..<ra.count {
                            let cell = ra[i]
                            let rawValue: String?
                            if var bytes = cell.bytes {
                                if let str = try? cell.decode(String.self) {
                                    rawValue = str
                                } else {
                                    rawValue = bytes.readString(length: bytes.readableBytes)
                                }
                            } else {
                                rawValue = nil
                            }
                            values.append(CellValue(
                                columnName: cell.columnName,
                                rawValue: rawValue,
                                dataType: cell.dataType.rawValue.description
                            ))
                        }
                        tableRows.append(TableRow(values: values))
                    }

                    result = .rows(QueryResult(
                        rows: tableRows, columns: columnInfos,
                        totalCount: Int64(tableRows.count), pageSize: tableRows.count,
                        currentOffset: 0, executionTimeMs: executionTime, query: trimmed
                    ))
                } else {
                    let rows = try await conn.query(trimmed)
                    for try await _ in rows { }
                    result = .message("Query executed successfully.")
                }
            } catch {
                result = .error(error.localizedDescription)
            }

            isExecuting = false
        }
    }
}

// MARK: - Console Results Grid

private struct ConsoleResultsGrid: View {
    let result: QueryResult

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(result.rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.values.enumerated()), id: \.offset) { _, cell in
                                Text(cell.displayValue)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(cell.isNull ? .secondary : .primary)
                                    .italic(cell.isNull)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .frame(width: 140, alignment: .leading)
                            }
                        }
                        .frame(height: GlintDesign.rowHeight)
                        .background(index % 2 == 1 ? GlintDesign.alternatingRow.opacity(0.5) : .clear)
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(result.columns) { col in
                            Text(col.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .frame(width: 140, alignment: .leading)
                        }
                    }
                    .frame(height: GlintDesign.headerHeight)
                    .background(.bar)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(result.totalCount) rows · \(String(format: "%.0f", result.executionTimeMs))ms")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(8)
        }
    }
}
