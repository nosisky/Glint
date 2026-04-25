import SwiftUI

/// Toolbar global search — introspects table schema for ILIKE across text/numeric columns.
struct GlobalSearchBar: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: GlintDesign.spacingSM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("Search all columns…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit {
                    Task { await appState.performGlobalSearch(searchText) }
                }
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty && !appState.globalSearchText.isEmpty {
                        Task { await appState.performGlobalSearch("") }
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await appState.performGlobalSearch("") }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, GlintDesign.spacingSM)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: GlintDesign.cornerRadiusMD)
                .fill(.quaternary.opacity(0.3))
        )
        .frame(width: 260)
        .animation(GlintDesign.snappy, value: searchText.isEmpty)
    }
}
