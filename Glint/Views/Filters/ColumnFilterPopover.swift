import SwiftUI

/// Column filter popover — shown from column header.
struct ColumnFilterPopover: View {
    let column: ColumnInfo
    @Environment(AppState.self) private var appState
    @State private var selectedOperation: FilterOperation = .equals
    @State private var filterText = ""
    @State private var rangeMin = ""
    @State private var rangeMax = ""
    @State private var distinctValues: [String?] = []
    @State private var isLoadingDistinct = false
    @State private var searchDistinct = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(column.name)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(column.dataType)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                // Operation
                Picker("Condition", selection: $selectedOperation) {
                    ForEach(availableOperations, id: \.self) { op in
                        Text(op.displayLabel).tag(op)
                    }
                }
                .pickerStyle(.menu)

                // Value
                if selectedOperation.requiresValue {
                    if selectedOperation == .between {
                        HStack {
                            TextField("Min", text: $rangeMin)
                                .textFieldStyle(.roundedBorder)
                            Text("–").foregroundStyle(.secondary)
                            TextField("Max", text: $rangeMax)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        TextField("Value…", text: $filterText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(12)

            Divider()

            // Distinct values
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Values")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isLoadingDistinct {
                        ProgressView().controlSize(.mini)
                    }
                }

                TextField("Search…", text: $searchDistinct)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredDistinctValues, id: \.self) { value in
                            Button {
                                filterText = value ?? ""
                                selectedOperation = value == nil ? .isNull : .equals
                            } label: {
                                Text(value ?? "NULL")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(value == nil ? GlintDesign.nullText : .primary)
                                    .italic(value == nil)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            .padding(12)

            Divider()

            // Actions
            HStack {
                Button("Clear") {
                    Task {
                        for f in appState.filters where f.columnName == column.name {
                            await appState.removeFilter(f.id)
                        }
                    }
                }

                Spacer()

                Button("Apply") { applyFilter() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApply)
            }
            .padding(12)
        }
        .frame(width: 260)
        .task { await loadDistinctValues() }
    }

    // MARK: - Helpers

    private var availableOperations: [FilterOperation] {
        if column.isNumeric {
            return [.equals, .notEquals, .greaterThan, .lessThan, .greaterOrEqual, .lessOrEqual, .between, .isNull, .isNotNull]
        } else if column.isBoolean {
            return [.equals, .isNull, .isNotNull]
        } else if column.isTemporal {
            return [.equals, .greaterThan, .lessThan, .between, .isNull, .isNotNull]
        } else {
            return [.equals, .notEquals, .contains, .startsWith, .endsWith, .isNull, .isNotNull]
        }
    }

    private var filteredDistinctValues: [String?] {
        if searchDistinct.isEmpty { return distinctValues }
        return distinctValues.filter { val in
            guard let v = val else { return "null".contains(searchDistinct.lowercased()) }
            return v.localizedCaseInsensitiveContains(searchDistinct)
        }
    }

    private var canApply: Bool {
        if !selectedOperation.requiresValue { return true }
        if selectedOperation == .between { return !rangeMin.isEmpty && !rangeMax.isEmpty }
        return !filterText.isEmpty
    }

    private func loadDistinctValues() async {
        guard let pool = appState.connectionPool, let table = appState.selectedTable else { return }
        isLoadingDistinct = true
        do {
            let conn = try await pool.getConnection()
            let introspector = SchemaIntrospector(connection: conn)
            distinctValues = try await introspector.fetchDistinctValues(
                schema: table.schema, table: table.name, column: column.name
            )
        } catch { distinctValues = [] }
        isLoadingDistinct = false
    }

    private func applyFilter() {
        let value: FilterValue
        switch selectedOperation {
        case .isNull, .isNotNull: value = .none
        case .between:
            if let lo = Double(rangeMin), let hi = Double(rangeMax) {
                value = .range(low: lo, high: hi)
            } else { return }
        default:
            if column.isNumeric, let num = Double(filterText) { value = .number(num) }
            else if column.isBoolean { value = .boolean(filterText.lowercased() == "true") }
            else { value = .text(filterText) }
        }

        Task {
            await appState.addFilter(FilterConstraint(
                columnName: column.name, columnType: column.udtName,
                operation: selectedOperation, value: value
            ))
        }
    }
}
