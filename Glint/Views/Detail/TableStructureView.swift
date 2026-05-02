import SwiftUI

struct TableStructureView: View {
    let table: TableInfo
    @Environment(AppState.self) private var appState
    @State private var detailedTable: TableInfo?
    @State private var indexes: [SchemaIntrospector.IndexResult] = []
    @State private var tableMeta: SchemaIntrospector.TableMeta?
    @State private var isLoading = true

    private var displayTable: TableInfo { detailedTable ?? table }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        tableHeader
                        Divider()
                        columnsSection
                        if !indexes.isEmpty {
                            indexesSection
                        }
                    }
                }
            }
        }
        .task { await loadStructure() }
    }

    // MARK: - Table Header

    private var tableHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TABLE NAME")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(displayTable.name)
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer()

            HStack(spacing: 16) {
                metaField("SCHEMA", value: displayTable.schema)
                if let meta = tableMeta {
                    metaField("TABLESPACE", value: meta.tablespace)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func metaField(_ label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Columns

    private var columnsSection: some View {
        VStack(spacing: 0) {
            columnHeaders
            ForEach(Array(displayTable.columns.enumerated()), id: \.element.id) { index, col in
                columnRow(col, index: index)
            }
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("COLUMN NAME")
                .frame(width: 180, alignment: .leading)
            Text("TYPE")
                .frame(width: 200, alignment: .leading)
            Text("DEFAULT")
                .frame(width: 240, alignment: .leading)
            Text("CONSTRAINTS")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func columnRow(_ col: ColumnInfo, index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(col.name)
                    .font(.system(size: 12, weight: col.isPrimaryKey ? .medium : .regular))
                    .frame(width: 180, alignment: .leading)

                Text(fullTypeName(col))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 200, alignment: .leading)

                defaultValueCell(col)
                    .frame(width: 240, alignment: .leading)

                constraintPills(col)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(index % 2 == 1
                ? GlintDesign.alternatingRow.opacity(0.5)
                : .clear
            )

            Divider().opacity(0.3)
        }
    }

    @ViewBuilder
    private func defaultValueCell(_ col: ColumnInfo) -> some View {
        if let def = col.defaultValue {
            HStack(spacing: 4) {
                Text("expression")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .systemGray).opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                Text(def)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text("no default")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .systemGray).opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
        }
    }

    @ViewBuilder
    private func constraintPills(_ col: ColumnInfo) -> some View {
        HStack(spacing: 4) {
            if let fk = col.foreignKey {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                    Text("\(fk.referencedTable).\(fk.referencedColumn)")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
            }

            if col.isPrimaryKey {
                Text("PRIMARY KEY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
            }

            if !col.isNullable {
                Text("NOT NULL")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .systemGray).opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
            }

            if let values = col.enumValues, !values.isEmpty {
                Text(values.joined(separator: " | "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(values.joined(separator: "\n"))
            }
        }
    }

    // MARK: - Indexes

    private var indexesSection: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Text("Indexes")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            indexHeaders

            ForEach(Array(indexes.enumerated()), id: \.offset) { index, idx in
                indexRow(idx, index: index)
            }
        }
    }

    private var indexHeaders: some View {
        HStack(spacing: 0) {
            Text("INDEX NAME")
                .frame(width: 220, alignment: .leading)
            Text("TYPE")
                .frame(width: 200, alignment: .leading)
            Text("COLUMNS")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func indexRow(_ idx: SchemaIntrospector.IndexResult, index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(idx.name)
                    .font(.system(size: 12))
                    .frame(width: 220, alignment: .leading)

                indexTypePill(idx)
                    .frame(width: 200, alignment: .leading)

                HStack(spacing: 4) {
                    ForEach(idx.columns, id: \.self) { col in
                        Text(col)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .systemGray).opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(index % 2 == 1
                ? GlintDesign.alternatingRow.opacity(0.5)
                : .clear
            )

            Divider().opacity(0.3)
        }
    }

    @ViewBuilder
    private func indexTypePill(_ idx: SchemaIntrospector.IndexResult) -> some View {
        let label: String
        let color: Color

        if idx.isPrimary {
            let _ = (label, color) = ("Primary Key Index", .orange)
        } else if idx.isUnique {
            let _ = (label, color) = ("Unique Index", .green)
        } else {
            let _ = (label, color) = ("Index", Color(nsColor: .systemGray))
        }

        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Helpers

    private func fullTypeName(_ col: ColumnInfo) -> String {
        if col.isEnum { return col.udtName }
        let base: String
        switch col.udtName.lowercased() {
        case "int2": base = "smallint"
        case "int4": base = "integer"
        case "int8": base = "bigint"
        case "float4": base = "real"
        case "float8": base = "double precision"
        case "bool": base = "boolean"
        case "varchar":
            if let max = col.characterMaxLength { base = "character varying(\(max))" }
            else { base = "character varying" }
        case "bpchar":
            if let max = col.characterMaxLength { base = "character(\(max))" }
            else { base = "character" }
        case "timestamptz": base = "timestamp with time zone"
        case "timetz": base = "time with time zone"
        default: base = col.udtName
        }
        return base
    }

    private func loadStructure() async {
        guard let pool = appState.connectionPool,
              let conn = try? await pool.getConnection()
        else {
            isLoading = false
            return
        }

        let introspector = SchemaIntrospector(connection: conn)

        async let updatedColumns: TableInfo? = appState.loadColumnsForTable(table)
        async let fetchedIndexes: [SchemaIntrospector.IndexResult] =
            (try? await introspector.fetchIndexes(schema: table.schema, table: table.name)) ?? []
        async let fetchedMeta: SchemaIntrospector.TableMeta? =
            try? await introspector.fetchTableMeta(schema: table.schema, table: table.name)

        if let cols = await updatedColumns { detailedTable = cols }
        indexes = await fetchedIndexes
        tableMeta = await fetchedMeta

        isLoading = false
    }
}
