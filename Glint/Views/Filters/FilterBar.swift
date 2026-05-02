//
//  FilterBar.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// Postico-style filter bar — sits above the data grid.
/// Column picker → Operator picker → Search field → Action buttons.
struct FilterBar: View {
    @Environment(AppState.self) private var appState
    @State private var selectedColumn: String = "__any__"
    @State private var selectedOperator: FilterOperation = .contains
    @State private var searchText: String = ""
    @State private var showSQLPreview = false
    @FocusState private var isSearchFocused: Bool

    private static let quickFilterOps: [FilterOperation] = [
        .contains, .equals, .startsWith, .endsWith, .isNull, .isNotNull
    ]

    private var columns: [ColumnInfo] {
        appState.selectedTable?.columns ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Picker("", selection: $selectedColumn) {
                    Text("Any Column").tag("__any__")
                    Divider()
                    ForEach(columns) { col in
                        Text(col.name).tag(col.name)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 130)

                Picker("", selection: $selectedOperator) {
                    ForEach(Self.quickFilterOps, id: \.self) { op in
                        Text(op.displayLabel).tag(op)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 100)

                if selectedOperator.requiresValue {
                    TextField("Value…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .focused($isSearchFocused)
                        .onSubmit { applyFilter() }
                }

                Spacer(minLength: 0)

                Button("Clear") {
                    clearFilter()
                }
                .controlSize(.small)
                .disabled(searchText.isEmpty && !appState.hasActiveFilters)

                Button("SQL") {
                    showSQLPreview.toggle()
                }
                .controlSize(.small)
                .popover(isPresented: $showSQLPreview) {
                    SQLPreviewPopover()
                }

                Button("Apply") {
                    applyFilter()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(selectedOperator.requiresValue && searchText.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(GlintDesign.panelBackground)

            Divider()
        }
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: - Actions

    private func applyFilter() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if selectedColumn == "__any__" {
            // Global search across all columns
            Task { await appState.performGlobalSearch(trimmed) }
        } else {
            // Targeted column filter
            guard let col = columns.first(where: { $0.name == selectedColumn }) else { return }

            let value: FilterValue
            let operation = selectedOperator

            switch selectedOperator {
            case .isNull, .isNotNull:
                value = .none
            default:
                if col.isNumeric, let num = Double(trimmed) {
                    value = .number(num)
                } else {
                    value = .text(trimmed)
                }
            }

            let constraint = FilterConstraint(
                columnName: col.name,
                columnType: col.udtName,
                operation: operation,
                value: value
            )

            Task { await appState.addFilter(constraint) }
        }

        // Clear search text after applying
        searchText = ""
    }

    private func clearFilter() {
        searchText = ""
        selectedColumn = "__any__"
        selectedOperator = .contains
        Task { await appState.clearAllFilters() }
    }
}

// MARK: - SQL Preview Popover

private struct SQLPreviewPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generated SQL")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            let query = appState.queryResult.query

            if query.isEmpty {
                Text("No active query.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    Text(query)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }

            HStack {
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(query, forType: .string)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 420)
    }
}
