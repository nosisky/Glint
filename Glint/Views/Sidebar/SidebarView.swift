import SwiftUI

/// Sidebar with schema browser — uses NSVisualEffectView material via .background(.ultraThinMaterial).
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
        .background(.ultraThinMaterial)
    }
}

// MARK: - Connected State

private struct ConnectedSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Database picker (if multiple databases available)
            if appState.databases.count > 1 {
                DatabasePicker()
            }

            // Table list
            List(selection: Binding(
                get: { appState.selectedTable },
                set: { table in
                    if let table {
                        Task { await appState.selectTable(table) }
                    }
                }
            )) {
                if appState.schemas.isEmpty && !appState.isLoadingSchema {
                    ContentUnavailableView {
                        Label("No Tables", systemImage: "tray")
                    } description: {
                        Text("This database has no tables.")
                    }
                } else {
                    ForEach(appState.schemas) { schema in
                        Section(schema.name) {
                            ForEach(schema.tables) { table in
                                TableSidebarRow(table: table)
                                    .tag(table)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Refresh Schema") {
                        Task { await appState.loadSchema() }
                    }

                    if appState.databases.count > 1 {
                        Menu("Switch Database") {
                            ForEach(appState.databases, id: \.self) { db in
                                Button {
                                    Task { await appState.switchDatabase(db) }
                                } label: {
                                    HStack {
                                        Text(db)
                                        if db == appState.currentDatabase {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                .disabled(db == appState.currentDatabase)
                            }
                        }
                    }

                    Divider()

                    Button("Disconnect", role: .destructive) {
                        Task { await appState.disconnect() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if appState.isLoadingSchema {
                VStack(spacing: GlintDesign.spacingSM) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading schema…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Database Picker

private struct DatabasePicker: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: GlintDesign.spacingSM) {
            Image(systemName: "cylinder")
                .font(.system(size: 11))
                .foregroundStyle(GlintDesign.gold)

            Picker("", selection: Binding(
                get: { appState.currentDatabase },
                set: { db in
                    Task { await appState.switchDatabase(db) }
                }
            )) {
                ForEach(appState.databases, id: \.self) { db in
                    Text(db).tag(db)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(.horizontal, GlintDesign.spacingMD)
        .padding(.vertical, GlintDesign.spacingSM)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Table Row

private struct TableSidebarRow: View {
    let table: TableInfo
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: GlintDesign.spacingSM) {
            Image(systemName: table.type.icon)
                .font(.system(size: 12))
                .foregroundStyle(table.type == .table ? GlintDesign.gold : .secondary)
                .frame(width: 16)

            Text(table.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            if let count = table.estimatedRowCount, count > 0 {
                Text(formatRowCount(count))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.04))
                    )
            }
        }
        .onHover { isHovered = $0 }
    }

    private func formatRowCount(_ count: Int64) -> String {
        if count >= 1_000_000 { return "\(count / 1_000_000)M" }
        if count >= 1_000 { return "\(count / 1_000)K" }
        return "\(count)"
    }
}

// MARK: - Disconnected State

private struct DisconnectedSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Connections") {
                ForEach(appState.savedConnections) { config in
                    ConnectionSidebarRow(config: config)
                }

                Button {
                    appState.showConnectionSheet = true
                } label: {
                    Label("Add Connection", systemImage: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if appState.savedConnections.isEmpty {
                VStack(spacing: GlintDesign.spacingSM) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text("No connections")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct ConnectionSidebarRow: View {
    let config: ConnectionConfig

    var body: some View {
        HStack(spacing: GlintDesign.spacingSM) {
            Circle()
                .fill(GlintDesign.tagColor(config.colorTag))
                .frame(width: 8, height: 8)
                .opacity(config.colorTag == .none ? 0 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 13, weight: .medium))
                Text("\(config.host)/\(config.database)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}
