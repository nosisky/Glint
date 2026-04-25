import SwiftUI

/// Opt-in raw SQL console — hidden by default, accessible from the menu.
/// Users who want raw SQL power can use this without leaving Glint.
struct RawConsoleView: View {
    @Environment(AppState.self) private var appState
    @State private var sqlText = ""
    @State private var result: ConsoleResult?
    @State private var isExecuting = false
    @State private var history: [String] = []
    @State private var historyIndex: Int?

    enum ConsoleResult {
        case rows(QueryResult)
        case message(String)
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // SQL editor
            VStack(alignment: .leading, spacing: GlintDesign.spacingSM) {
                HStack {
                    Text("SQL Console")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    if isExecuting {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Button {
                        executeQuery()
                    } label: {
                        Label("Execute", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(GlintButtonStyle(isPrimary: true))
                    .disabled(sqlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExecuting)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                }

                TextEditor(text: $sqlText)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(GlintDesign.spacingSM)
                    .background(
                        RoundedRectangle(cornerRadius: GlintDesign.cornerRadiusMD)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: GlintDesign.cornerRadiusMD)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .frame(minHeight: 80, maxHeight: 200)
            }
            .padding(GlintDesign.spacingMD)

            Divider()

            // Results
            Group {
                if let result {
                    switch result {
                    case .rows(let queryResult):
                        ConsoleResultsGrid(result: queryResult)
                    case .message(let msg):
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(GlintDesign.success)
                            Text(msg)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(GlintDesign.spacingMD)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    case .error(let err):
                        HStack(alignment: .top) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(GlintDesign.error)
                            Text(err)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(GlintDesign.error)
                                .textSelection(.enabled)
                        }
                        .padding(GlintDesign.spacingMD)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(spacing: GlintDesign.spacingSM) {
                        Image(systemName: "terminal")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(.quaternary)
                        Text("⌘⇧↩ to execute")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(GlintDesign.background)
    }

    private func executeQuery() {
        let trimmed = sqlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isExecuting = true
        history.append(trimmed)

        Task {
            guard let pool = appState.connectionPool else {
                result = .error("Not connected to a database.")
                isExecuting = false
                return
            }

            do {
                let conn = try await pool.getConnection()
                let isSelect = trimmed.uppercased().hasPrefix("SELECT")
                    || trimmed.uppercased().hasPrefix("WITH")

                if isSelect {
                    // Fetch rows for display
                    let startTime = CFAbsoluteTimeGetCurrent()
                    let rows = try await conn.queryAll(trimmed)
                    let executionTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

                    // Materialize rows — build columns from first row
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
                                isNullable: true,
                                isPrimaryKey: false,
                                hasDefault: false,
                                defaultValue: nil,
                                characterMaxLength: nil,
                                numericPrecision: nil,
                                ordinalPosition: i
                            ))
                        }
                    }

                    for row in rows {
                        let randomAccess = row.makeRandomAccess()
                        var values: [CellValue] = []
                        for i in 0..<randomAccess.count {
                            let cell = randomAccess[i]
                            let rawValue: String? = cell.bytes == nil ? nil : (try? cell.decode(String.self))
                            values.append(CellValue(
                                columnName: cell.columnName,
                                rawValue: rawValue,
                                dataType: cell.dataType.rawValue.description
                            ))
                        }
                        tableRows.append(TableRow(values: values))
                    }

                    result = .rows(QueryResult(
                        rows: tableRows,
                        columns: columnInfos,
                        totalCount: Int64(tableRows.count),
                        pageSize: tableRows.count,
                        currentOffset: 0,
                        executionTimeMs: executionTime,
                        query: trimmed
                    ))
                } else {
                    // DML/DDL — just execute
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
                                    .foregroundStyle(cell.isNull ? GlintDesign.nullValue : .primary)
                                    .italic(cell.isNull)
                                    .lineLimit(1)
                                    .padding(.horizontal, GlintDesign.spacingSM)
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
                                .padding(.horizontal, GlintDesign.spacingSM)
                                .frame(width: 140, alignment: .leading)
                        }
                    }
                    .frame(height: GlintDesign.headerHeight)
                    .background(.bar)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(result.totalCount) rows · \(String(format: "%.1f", result.executionTimeMs))ms")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(GlintDesign.spacingSM)
        }
    }
}
