import SwiftUI

/// Table structure inspector — shows columns, types, constraints, and indexes.
/// Accessible from the sidebar context menu or a toolbar button.
struct TableStructureView: View {
    let table: TableInfo
    @Environment(AppState.self) private var appState
    @State private var detailedTable: TableInfo?
    @State private var isLoading = true

    var displayTable: TableInfo {
        detailedTable ?? table
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: table.type.icon)
                    .foregroundStyle(GlintDesign.gold)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(table.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(table.schema) · \(table.type.rawValue.lowercased())")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let count = table.estimatedRowCount {
                    Text("~\(count.formattedCount) rows")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.04)))
                }
            }
            .padding(GlintDesign.spacingLG)
            .background(.bar)

            Divider()

            // Column list
            if isLoading {
                ProgressView("Loading structure…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Header row
                        HStack(spacing: 0) {
                            structureHeaderCell("Column", width: 180)
                            structureHeaderCell("Type", width: 140)
                            structureHeaderCell("Nullable", width: 80)
                            structureHeaderCell("Default", width: 160)
                            structureHeaderCell("Key", width: 60)
                        }
                        .frame(height: GlintDesign.headerHeight)
                        .background(.bar)

                        Divider()

                        ForEach(Array(displayTable.columns.enumerated()), id: \.element.id) { index, column in
                            ColumnStructureRow(column: column, isAlternate: index % 2 == 1)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 300)
        .task {
            if let updated = await appState.loadColumnsForTable(table) {
                detailedTable = updated
            }
            isLoading = false
        }
    }

    private func structureHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, GlintDesign.spacingSM)
    }
}

// MARK: - Column Row

private struct ColumnStructureRow: View {
    let column: ColumnInfo
    let isAlternate: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Column name
            HStack(spacing: GlintDesign.spacingXS) {
                Image(systemName: column.typeIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(column.isPrimaryKey ? AnyShapeStyle(GlintDesign.gold) : AnyShapeStyle(.tertiary))
                    .frame(width: 14)

                Text(column.name)
                    .font(.system(size: 12, weight: column.isPrimaryKey ? .semibold : .regular))
            }
            .frame(width: 180, alignment: .leading)
            .padding(.horizontal, GlintDesign.spacingSM)

            // Type
            HStack(spacing: 4) {
                Text(PostgresTypeMapper.displayName(for: column.udtName))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)

                if let maxLen = column.characterMaxLength {
                    Text("(\(maxLen))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 140, alignment: .leading)
            .padding(.horizontal, GlintDesign.spacingSM)

            // Nullable
            Group {
                if column.isNullable {
                    Text("YES")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("NOT NULL")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GlintDesign.warning)
                }
            }
            .frame(width: 80, alignment: .leading)
            .padding(.horizontal, GlintDesign.spacingSM)

            // Default
            Text(column.defaultValue ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(column.hasDefault ? .primary : .quaternary)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)
                .padding(.horizontal, GlintDesign.spacingSM)

            // Key
            Group {
                if column.isPrimaryKey {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(GlintDesign.gold)
                }
            }
            .frame(width: 60, alignment: .leading)
            .padding(.horizontal, GlintDesign.spacingSM)
        }
        .frame(height: GlintDesign.rowHeight)
        .background(isAlternate ? GlintDesign.alternatingRow.opacity(0.5) : .clear)
    }
}
