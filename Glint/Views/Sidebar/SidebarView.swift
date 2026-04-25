import SwiftUI

/// Sidebar — Postico-style: search bar + flat table list.
struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isConnected {
                ConnectedSidebar()
            } else {
                DisconnectedSidebar()
            }
        }
    }
}

// MARK: - Connected

private struct ConnectedSidebar: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var filteredSchemas: [DatabaseSchemaInfo] {
        if searchText.isEmpty { return appState.schemas }
        return appState.schemas.compactMap { schema in
            let filtered = schema.tables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            if filtered.isEmpty { return nil }
            return DatabaseSchemaInfo(name: schema.name, tables: filtered)
        }
    }

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedTable },
            set: { table in
                if let table { Task { await appState.selectTable(table) } }
            }
        )) {
            let schemas = filteredSchemas
            let showSections = schemas.count > 1

            ForEach(schemas) { schema in
                if showSections {
                    Section(schema.name) {
                        tableList(schema.tables)
                    }
                } else {
                    tableList(schema.tables)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await appState.loadSchema() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Schema")
            }
        }
        .overlay {
            if appState.isLoadingSchema {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private func tableList(_ tables: [TableInfo]) -> some View {
        ForEach(tables) { table in
            HStack(spacing: 6) {
                Image(systemName: table.type.icon)
                    .font(.system(size: 10))
                    .foregroundColor(table.type == .view ? .secondary : .accentColor)
                    .frame(width: 14)

                Text(table.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .tag(table)
        }
    }
}

// MARK: - Disconnected

private struct DisconnectedSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Saved") {
                ForEach(appState.savedConnections) { config in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.name)
                            .font(.system(size: 13))
                        Text("\(config.host):\(config.port)/\(config.database)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
