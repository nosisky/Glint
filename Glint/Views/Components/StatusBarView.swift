import SwiftUI

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: GlintDesign.spacingMD) {
            HStack(spacing: GlintDesign.spacingXS) {
                Circle()
                    .fill(appState.isConnected ? GlintDesign.success : .gray)
                    .frame(width: 6, height: 6)
                Text(appState.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if appState.hasPendingEdits {
                HStack(spacing: GlintDesign.spacingXS) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(GlintDesign.gold)
                        .font(.system(size: 11))
                    Text("\(appState.pendingEdits.count) pending")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GlintDesign.gold)
                }
            }
        }
    }
}

struct PaginationBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            Text("\(appState.queryResult.totalCount) rows")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            if appState.queryResult.totalPages > 1 {
                HStack(spacing: GlintDesign.spacingSM) {
                    Button { Task { await appState.previousPage() } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain).disabled(appState.currentPage <= 1)

                    Text("Page \(appState.currentPage) of \(appState.queryResult.totalPages)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)

                    Button { Task { await appState.nextPage() } } label: {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain).disabled(!appState.queryResult.hasMore)
                }
            }
            Spacer()
            if appState.queryResult.executionTimeMs > 0 {
                Text("\(String(format: "%.1f", appState.queryResult.executionTimeMs))ms")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, GlintDesign.spacingMD)
        .padding(.vertical, GlintDesign.spacingSM)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
