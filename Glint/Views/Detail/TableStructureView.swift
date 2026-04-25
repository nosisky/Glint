import SwiftUI

/// Table structure inspector — shows columns with type awareness,
/// FK relationships, enum values, and constraints.
struct TableStructureView: View {
    let table: TableInfo
    @Environment(AppState.self) private var appState
    @State private var detailedTable: TableInfo?
    @State private var isLoading = true

    private var displayTable: TableInfo { detailedTable ?? table }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(displayTable.columns) {
                    TableColumn("#") { col in
                        Text("\(col.ordinalPosition)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                    .width(30)

                    TableColumn("Column") { col in
                        HStack(spacing: 5) {
                            // Constraint indicators
                            if col.isPrimaryKey {
                                Text("PK")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.orange)
                            }
                            if col.isForeignKey {
                                Text("FK")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.blue)
                            }

                            Text(col.name)
                                .font(.system(size: 12))
                                .fontWeight(col.isPrimaryKey ? .medium : .regular)
                        }
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Type") { col in
                        Text(col.typeLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 130)

                    TableColumn("Nullable") { col in
                        Text(col.isNullable ? "YES" : "NOT NULL")
                            .font(.system(size: 11))
                            .foregroundStyle(col.isNullable ? .tertiary : .primary)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Default") { col in
                        if let def = col.defaultValue {
                            Text(def)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("—")
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .width(min: 80, ideal: 160)

                    TableColumn("References") { col in
                        if let fk = col.foreignKey {
                            HStack(spacing: 2) {
                                Text("→")
                                    .foregroundStyle(.blue)
                                Text("\(fk.referencedTable).\(fk.referencedColumn)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 60, ideal: 180)

                    TableColumn("Enum Values") { col in
                        if let values = col.enumValues {
                            Text(values.joined(separator: ", "))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(values.joined(separator: "\n"))
                        }
                    }
                    .width(min: 60, ideal: 200)
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
