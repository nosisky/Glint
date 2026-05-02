//
//  ForeignKeyPreviewPopover.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

struct ForeignKeyPreviewPopover: View {
    let table: TableInfo
    let referencedColumn: String
    let value: String
    let onClose: () -> Void
    let onPick: (String) -> Void
    @Environment(AppState.self) private var appState

    @State private var result: QueryResult?
    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var page = 0
    private let limit = 100

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "hand.point.up.left")
                    .foregroundColor(.accentColor)
                Text("Select \(referencedColumn)")
                    .font(.system(size: 13, weight: .semibold))
                Text("from")
                    .foregroundColor(.secondary)
                Text(table.name)
                    .font(.system(size: 13, design: .monospaced))
                Spacer()
                
                // Deep link button
                Button("Go to Table") {
                    onClose()
                    Task {
                        await appState.selectTable(table)
                        await appState.addFilter(FilterConstraint(
                            columnName: referencedColumn,
                            columnType: "text",
                            operation: .equals,
                            value: .text(value)
                        ))
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(GlintDesign.quietAccent)
                .foregroundColor(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            // Content
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Fetching records...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 150)
            } else if let errorMsg {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(errorMsg)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 150)
            } else if let result {
                DataGridView(
                    customResult: result,
                    customTable: table,
                    isPickerMode: true,
                    initialSelection: value,
                    onRowPicked: handlePick
                )
                .frame(minHeight: 300)
                
                Divider()
                
                // Pagination Footer
                HStack {
                    Text("Double-click a row to select")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        if page > 0 {
                            page -= 1
                            Task { await fetchPage() }
                        }
                    }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(page == 0)
                    .controlSize(.small)
                    
                    Text("Page \(page + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .center)
                    
                    Button(action: {
                        if result.rows.count == limit {
                            page += 1
                            Task { await fetchPage() }
                        }
                    }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(result.rows.count < limit)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 700, height: 450)
        .task {
            await fetchPage()
        }
    }

    private func handlePick(_ row: TableRow) {
        // Find the referenced column in the row
        guard let cell = row.values.first(where: { $0.columnName == referencedColumn }) else { return }
        if let val = cell.rawValue {
            onPick(val)
        }
    }

    private func fetchPage() async {
        isLoading = true
        errorMsg = nil
        do {
            guard let pool = appState.connectionPool else {
                throw NSError(domain: "Glint", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active connection"])
            }
            let conn = try await pool.getConnection()
            let fetcher = DataFetcher(connection: conn)
            self.result = try await fetcher.fetchTablePage(table: table, limit: limit, offset: page * limit)
        } catch {
            self.errorMsg = error.localizedDescription
        }
        isLoading = false
    }
}
