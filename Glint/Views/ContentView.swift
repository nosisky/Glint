import SwiftUI

/// Main content view — NavigationSplitView with sidebar + detail layout.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if appState.isConnected {
                if appState.selectedTable != nil {
                    DataGridContainer()
                } else {
                    WelcomeDetailView()
                }
            } else {
                WelcomeView()
            }
        }
        .navigationTitle(appState.activeConfig?.name ?? "Glint")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if appState.isConnected {
                    GlobalSearchBar()
                }
            }

            ToolbarItemGroup(placement: .status) {
                StatusBarView()
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

// MARK: - Welcome Views

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: GlintDesign.spacingXL) {
            Image(systemName: "sparkle")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(GlintDesign.gold)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))

            VStack(spacing: GlintDesign.spacingSM) {
                Text("Glint")
                    .font(.system(size: 32, weight: .semibold, design: .default))
                    .tracking(1.5)
                Text("PostgreSQL, without the SQL.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            Button {
                appState.showConnectionSheet = true
            } label: {
                Label("New Connection", systemImage: "plus.circle.fill")
            }
            .buttonStyle(GlintButtonStyle(isPrimary: true))
            .keyboardShortcut("n", modifiers: [.command])

            if !appState.savedConnections.isEmpty {
                VStack(spacing: GlintDesign.spacingSM) {
                    Text("Recent Connections")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    ForEach(appState.savedConnections.prefix(5)) { config in
                        SavedConnectionRow(config: config)
                    }
                }
                .padding(.top, GlintDesign.spacingLG)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlintDesign.background)
    }
}

struct SavedConnectionRow: View {
    let config: ConnectionConfig
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var password = ""
    @State private var showPasswordPrompt = false

    var body: some View {
        Button {
            promptForPassword()
        } label: {
            HStack(spacing: GlintDesign.spacingSM) {
                Circle()
                    .fill(GlintDesign.tagColor(config.colorTag))
                    .frame(width: 8, height: 8)
                    .opacity(config.colorTag == .none ? 0 : 1)

                Image(systemName: "server.rack")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(config.host):\(config.port)/\(config.database)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, GlintDesign.spacingMD)
            .padding(.vertical, GlintDesign.spacingSM)
            .background {
                RoundedRectangle(cornerRadius: GlintDesign.cornerRadiusMD)
                    .fill(isHovered ? Color.primary.opacity(0.04) : .clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .frame(maxWidth: 360)
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

struct WelcomeDetailView: View {
    var body: some View {
        VStack(spacing: GlintDesign.spacingLG) {
            Image(systemName: "table")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text("Select a table from the sidebar")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlintDesign.background)
    }
}
