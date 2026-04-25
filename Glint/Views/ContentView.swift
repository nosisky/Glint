import SwiftUI

/// Main layout — Postico-style: toolbar with DB picker, sidebar with search, bottom bar.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if appState.isConnected {
                if appState.selectedTable != nil {
                    TableContentArea()
                } else {
                    SelectTablePrompt()
                }
            } else {
                WelcomeView()
            }
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle(windowSubtitle)
        .toolbar {
            // Database picker — Postico-style with icon
            ToolbarItem(placement: .principal) {
                if appState.isConnected {
                    HStack(spacing: 12) {
                        // DB picker
                        HStack(spacing: 4) {
                            Image(systemName: "cylinder")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

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
                                .frame(minWidth: 120)
                            } else {
                                Text(appState.currentDatabase)
                                    .font(.system(size: 13))
                            }
                        }

                        // Connection status
                        if appState.isConnecting {
                            ProgressView().controlSize(.small)
                        } else {
                            HStack(spacing: 4) {
                                Text("Connected")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)

                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)

                                Button {
                                    Task { await appState.loadSchema() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Refresh Schema")
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $state.showConnectionSheet) {
            ConnectionSheet()
        }
        .onAppear {
            appState.loadSavedConnections()
        }
    }

    private var windowTitle: String {
        if let table = appState.selectedTable {
            return table.name
        }
        return appState.isConnected ? appState.currentDatabase : "Glint"
    }

    private var windowSubtitle: String {
        if appState.selectedTable != nil, let config = appState.activeConfig {
            return "\(config.name) – \(appState.currentDatabase)"
        }
        return ""
    }
}

// MARK: - Table Content Area (filter bar + grid + bottom bar)

struct TableContentArea: View {
    @Environment(AppState.self) private var appState
    @State private var tab: ContentTab = .content

    enum ContentTab: String, CaseIterable {
        case content = "Content"
        case structure = "Structure"
        case ddl = "DDL"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar — toggled by bottom bar button
            if appState.showFilterBar && tab == .content {
                FilterBar()
            }

            // Main content
            switch tab {
            case .content:
                DataGridView()
            case .structure:
                if let table = appState.selectedTable {
                    TableStructureView(table: table)
                }
            case .ddl:
                DDLView()
            }

            // Bottom bar — Postico-style
            BottomBar(tab: $tab)
        }
    }
}

// MARK: - Bottom Bar

private struct BottomBar: View {
    @Binding var tab: TableContentArea.ContentTab
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            // Content / Structure / DDL tabs
            HStack(spacing: 0) {
                ForEach(TableContentArea.ContentTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 11, weight: tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(tab == t ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }

            // + Row
            Button {
                appState.insertNewRow()
            } label: {
                Text("+ Row")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

            Spacer()

            // Row count
            if tab == .content && appState.queryResult.totalCount > 0 {
                Text("\(appState.queryResult.totalCount) rows")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 12)
            }

            // Pending edits
            if appState.hasPendingEdits {
                HStack(spacing: 6) {
                    Button("Discard") {
                        appState.discardEdits()
                    }
                    .controlSize(.small)

                    Button("Save \(appState.pendingEdits.count) Change\(appState.pendingEdits.count == 1 ? "" : "s")") {
                        Task { await appState.commitEdits() }
                    }
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
                .padding(.trailing, 8)
            }

            // Filter toggle button — stays blue when filter bar is open
            if tab == .content {
                Button {
                    appState.showFilterBar.toggle()
                } label: {
                    Text("Filter")
                        .font(.system(size: 11, weight: appState.showFilterBar ? .semibold : .regular))
                        .foregroundStyle(appState.showFilterBar || appState.hasActiveFilters ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            appState.showFilterBar || appState.hasActiveFilters
                                ? Color.accentColor
                                : .clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            // Pagination
            if tab == .content && appState.queryResult.totalPages > 1 {
                HStack(spacing: 4) {
                    Button {
                        Task { await appState.previousPage() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.currentPage <= 1)

                    Text("Page \(appState.currentPage) of \(appState.queryResult.totalPages)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await appState.nextPage() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.queryResult.hasMore)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - DDL View (placeholder)

private struct DDLView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let table = appState.selectedTable {
            ScrollView {
                Text(generateDDL(table))
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    private func generateDDL(_ table: TableInfo) -> String {
        var ddl = "CREATE TABLE \(table.qualifiedName) (\n"
        for (i, col) in table.columns.enumerated() {
            ddl += "    \"\(col.name)\" \(col.dataType)"
            if !col.isNullable { ddl += " NOT NULL" }
            if let def = col.defaultValue { ddl += " DEFAULT \(def)" }
            if i < table.columns.count - 1 { ddl += "," }
            ddl += "\n"
        }
        let pks = table.columns.filter(\.isPrimaryKey).map { "\"\($0.name)\"" }
        if !pks.isEmpty {
            ddl += "    , PRIMARY KEY (\(pks.joined(separator: ", ")))\n"
        }
        ddl += ");\n"
        return ddl
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bolt.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Glint")
                .font(.system(size: 22, weight: .medium))

            Text("Connect to a PostgreSQL server to get started.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button("New Connection") {
                appState.showConnectionSheet = true
            }
            .controlSize(.large)

            if !appState.savedConnections.isEmpty {
                Divider()
                    .frame(width: 200)
                    .padding(.top, 8)

                VStack(spacing: 4) {
                    ForEach(appState.savedConnections) { config in
                        SavedConnectionRow(config: config)
                    }
                }
                .frame(maxWidth: 320)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SavedConnectionRow: View {
    let config: ConnectionConfig
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var password = ""
    @State private var showPasswordPrompt = false

    var body: some View {
        Button { promptForPassword() } label: {
            HStack(spacing: 8) {
                if config.colorTag != .none {
                    Circle()
                        .fill(GlintDesign.tagColor(config.colorTag))
                        .frame(width: 6, height: 6)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(config.name)
                        .font(.system(size: 13))
                    Text("\(config.host):\(config.port)/\(config.database)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .alert("Enter Password", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $password)
            Button("Connect") {
                Task { await appState.connect(config: config, password: password) }
            }
            Button("Cancel", role: .cancel) { password = "" }
        }
    }

    private func promptForPassword() {
        if let saved = try? KeychainService.readPassword(account: config.keychainAccount) {
            Task { await appState.connect(config: config, password: saved) }
        } else {
            showPasswordPrompt = true
        }
    }
}

struct SelectTablePrompt: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("Select a table")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
