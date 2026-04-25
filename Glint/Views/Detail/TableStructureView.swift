import SwiftUI

/// Table structure inspector — simple column list.
struct TableStructureView: View {
    let table: TableInfo
    @Environment(AppState.self) private var appState
    @State private var detailedTable: TableInfo?
    @State private var isLoading = true

    var displayTable: TableInfo { detailedTable ?? table }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(displayTable.columns) {
                    TableColumn("Column") { col in
                        HStack(spacing: 6) {
                            if col.isPrimaryKey {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                            }
                            Text(col.name)
                                .font(.system(size: 12))
                        }
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Type") { col in
                        Text(col.udtName)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Nullable") { col in
                        Text(col.isNullable ? "YES" : "NOT NULL")
                            .font(.system(size: 11))
                            .foregroundStyle(col.isNullable ? .secondary : .primary)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Default") { col in
                        Text(col.defaultValue ?? "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 160)
                }
            }
        }
        .task {
            if let updated = await appState.loadColumnsForTable(table) {
                detailedTable = updated
            }
            isLoading = false
        }
    }
}
