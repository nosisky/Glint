//
//  ActiveFiltersBar.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// Active filters — simple horizontal pills.
struct ActiveFiltersBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !appState.globalSearchText.isEmpty {
                    FilterPill(
                        text: "Search \(appState.globalSearchText)",
                        icon: "magnifyingglass"
                    ) {
                        Task { await appState.performGlobalSearch("") }
                    }
                }

                ForEach(appState.filters) { filter in
                    FilterPill(
                        text: "\(filter.columnName) \(filter.operation.symbol) \(filter.displayValue)",
                        icon: "line.3.horizontal.decrease"
                    ) {
                        Task { await appState.removeFilter(filter.id) }
                    }
                }

                if appState.filters.count > 1 {
                    Button("Clear All") {
                        Task { await appState.clearAllFilters() }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(GlintDesign.panelBackground.opacity(0.72))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct FilterPill: View {
    let text: String
    let icon: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))

            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(GlintDesign.quietAccent, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(GlintDesign.hairline, lineWidth: 1)
        )
    }
}
