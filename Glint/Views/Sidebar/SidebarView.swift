import SwiftUI

/// Sidebar — clean table list. Postico-style: just the table names.
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

    var body: some View {
        VStack(spacing: 0) {
            // Database picker
            if appState.databases.count > 1 {
                Picker("", selection: Binding(
                    get: { appState.currentDatabase },
                    set: { db in Task { await appState.switchDatabase(db) } }
                )) {
                    ForEach(appState.databases, id: \.self) { db in
                        Text(db).tag(db)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // Table list
            List(selection: Binding(
                get: { appState.selectedTable },
                set: { table in
                    if let table { Task { await appState.selectTable(table) } }
                }
            )) {
                ForEach(appState.schemas) { schema in
                    let showHeader = appState.schemas.count > 1

                    if showHeader {
                        Section(schema.name) {
                            tableRows(schema.tables)
                        }
                    } else {
                        tableRows(schema.tables)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Refresh") {
                        Task { await appState.loadSchema() }
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                    if appState.databases.count > 1 {
                        Divider()
                        Menu("Database") {
                            ForEach(appState.databases, id: \.self) { db in
                                Button(db) { Task { await appState.switchDatabase(db) } }
                                    .disabled(db == appState.currentDatabase)
                            }
                        }
                    }

                    Divider()

                    Button("Disconnect") {
                        Task { await appState.disconnect() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
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
    private func tableRows(_ tables: [TableInfo]) -> some View {
        ForEach(tables) { table in
            Label {
                Text(table.name)
                    .lineLimit(1)
            } icon: {
                Image(systemName: table.type.icon)
                    .foregroundStyle(table.type == .view ? .secondary : .primary)
                    .font(.system(size: 11))
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
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(config.name)
                                .font(.system(size: 13))
                            Text(config.host)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    } icon: {
                        if config.colorTag != .none {
                            Circle()
                                .fill(GlintDesign.tagColor(config.colorTag))
                                .frame(width: 8, height: 8)
                        } else {
                            Image(systemName: "server.rack")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
