import SwiftUI

/// Main content — NavigationSplitView with sidebar + detail.
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
                    DataGridContainer()
                } else {
                    SelectTablePrompt()
                }
            } else {
                WelcomeView()
            }
        }
        .navigationTitle(appState.isConnected ? appState.currentDatabase : "Glint")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if appState.isConnected {
                    GlobalSearchBar()
                }
            }

            ToolbarItem(placement: .status) {
                Text(appState.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $state.showConnectionSheet) {
            ConnectionSheet()
        }
        .onAppear {
            appState.loadSavedConnections()
        }
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
