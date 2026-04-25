import SwiftUI

/// Pill-based display of active filters with remove buttons.
struct ActiveFiltersBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GlintDesign.spacingSM) {
                if !appState.globalSearchText.isEmpty {
                    FilterPill(
                        icon: "magnifyingglass",
                        label: "Search: \(appState.globalSearchText)",
                        color: .blue
                    ) {
                        Task { await appState.performGlobalSearch("") }
                    }
                }

                ForEach(appState.filters) { filter in
                    FilterPill(
                        icon: "line.3.horizontal.decrease",
                        label: "\(filter.columnName) \(filter.operation.displayLabel) \(filter.value.displayString)",
                        color: GlintDesign.gold
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, GlintDesign.spacingMD)
            .padding(.vertical, GlintDesign.spacingSM)
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct FilterPill: View {
    let icon: String
    let label: String
    let color: Color
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: GlintDesign.spacingXS) {
            Image(systemName: icon)
                .font(.system(size: 9))

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.6)
        }
        .padding(.horizontal, GlintDesign.spacingSM)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
        )
        .foregroundStyle(color)
        .onHover { isHovered = $0 }
    }
}
