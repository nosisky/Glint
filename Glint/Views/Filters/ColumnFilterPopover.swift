import SwiftUI

/// Column filter popover — shown when clicking a column header's filter icon.
/// Contains distinct values list and logic toggles.
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
                Image(systemName: column.typeIcon)
                    .foregroundStyle(GlintDesign.gold)
                Text(column.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(column.dataType)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(GlintDesign.spacingMD)
            .background(.bar)

            Divider()

            // Operation picker
            VStack(alignment: .leading, spacing: GlintDesign.spacingSM) {
                Text("Condition")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Picker("", selection: $selectedOperation) {
                    ForEach(availableOperations, id: \.self) { op in
                        Text(op.displayLabel).tag(op)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(GlintDesign.spacingMD)

            // Value input
            if selectedOperation.requiresValue {
                VStack(alignment: .leading, spacing: GlintDesign.spacingSM) {
                    if selectedOperation == .between {
                        HStack {
                            TextField("Min", text: $rangeMin)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Text("–")
                                .foregroundStyle(.secondary)
                            TextField("Max", text: $rangeMax)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    } else {
                        TextField("Value…", text: $filterText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                .padding(.horizontal, GlintDesign.spacingMD)
            }

            Divider()
                .padding(.vertical, GlintDesign.spacingSM)

            // Distinct values
            VStack(alignment: .leading, spacing: GlintDesign.spacingSM) {
                HStack {
                    Text("Unique Values")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    if isLoadingDistinct {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                TextField("Filter values…", text: $searchDistinct)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredDistinctValues, id: \.self) { value in
                            Button {
                                filterText = value ?? ""
                                selectedOperation = .equals
                            } label: {
                                Text(value ?? "NULL")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(value == nil ? GlintDesign.nullValue : .primary)
                                    .italic(value == nil)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, GlintDesign.spacingSM)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.primary.opacity(0.001)) // hit target
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            .padding(.horizontal, GlintDesign.spacingMD)

            Divider()
                .padding(.vertical, GlintDesign.spacingSM)

            // Actions
            HStack {
                Button("Clear") {
                    // Remove any existing filter for this column
                    Task {
                        let existing = appState.filters.filter { $0.columnName == column.name }
                        for f in existing {
                            await appState.removeFilter(f.id)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Apply") {
                    applyFilter()
                }
                .buttonStyle(GlintButtonStyle(isPrimary: true))
                .disabled(!canApply)
            }
            .padding(GlintDesign.spacingMD)
        }
        .frame(width: 280)
        .task {
            await loadDistinctValues()
        }
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
                schema: table.schema,
                table: table.name,
                column: column.name
            )
        } catch {
            distinctValues = []
        }
        isLoadingDistinct = false
    }

    private func applyFilter() {
        let value: FilterValue
        switch selectedOperation {
        case .isNull, .isNotNull:
            value = .none
        case .between:
            if let lo = Double(rangeMin), let hi = Double(rangeMax) {
                value = .range(low: lo, high: hi)
            } else { return }
        default:
            if column.isNumeric, let num = Double(filterText) {
                value = .number(num)
            } else if column.isBoolean {
                value = .boolean(filterText.lowercased() == "true")
            } else {
                value = .text(filterText)
            }
        }

        let constraint = FilterConstraint(
            columnName: column.name,
            columnType: column.udtName,
            operation: selectedOperation,
            value: value
        )

        Task { await appState.addFilter(constraint) }
    }
}
