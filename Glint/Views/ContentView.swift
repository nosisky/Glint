//
//  ContentView.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        ZStack {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            } detail: {
            if appState.isConnected {
                VStack(spacing: 0) {
                    TabBarView()
                    
                    if appState.isQueryEditorOpen {
                        QueryEditorView()
                    } else if appState.isActivityMonitorOpen {
                        ActivityMonitorView()
                    } else if appState.selectedTable != nil {
                        TableContentArea()
                    } else if let function = appState.selectedFunction {
                        FunctionDetailView(function: function)
                    } else {
                        SelectTablePrompt()
                    }
                }
            } else {
                WelcomeView()
            }
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle(windowSubtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if appState.isConnected {
                    HStack {
                        if appState.selectedTable != nil {
                            Menu {
                                Button("Export as CSV...") {
                                    Task { await appState.exportTableAsCSV() }
                                }
                                Button("Export as JSON...") {
                                    Task { await appState.exportTableAsJSON() }
                                }
                            } label: {
                                if appState.isExporting {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                            }
                            .disabled(appState.isExporting)
                            .help("Export Table")
                        }
                        Button {
                            appState.toggleQueryEditor()
                        } label: {
                            Label("SQL Query", systemImage: "terminal")
                                .foregroundColor(appState.isQueryEditorOpen ? .accentColor : .primary)
                        }
                        .help("Toggle SQL Query Editor")
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                        
                        Button {
                            appState.toggleActivityMonitor()
                        } label: {
                            Label("Activity Monitor", systemImage: "waveform.path.ecg")
                                .foregroundColor(appState.isActivityMonitorOpen ? .accentColor : .primary)
                        }
                        .help("Toggle Activity Monitor")
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                        
                        Button {
                            Task { await appState.loadSchema() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh Schema")
                        
                        Button {
                            appState.addNewTab()
                        } label: {
                            Label("New Tab", systemImage: "plus")
                        }
                        .help("Open New Tab")
                    }
                }
            }
        }
        
        // Custom Overlay for the Connection Sheet
        if appState.showConnectionSheet {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.showConnectionSheet = false
                }
                .zIndex(1)
            
            ConnectionSheet()
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(2)
        }
        }
        .onAppear {
            appState.loadSavedConnections()
        }
        .alert("Database Error", isPresented: appState.hasError, presenting: appState.activeError) { _ in
            Button("OK", role: .cancel) { }
        } message: { errorMsg in
            Text(errorMsg)
        }
    }

    private var windowTitle: String {
        if let table = appState.selectedTable { return table.name }
        if appState.isConnected { return appState.currentDatabase }
        return "Glint"
    }

    private var windowSubtitle: String {
        guard appState.isConnected else { return "" }
        var parts: [String] = []
        if appState.isConnecting {
            parts.append("Connecting…")
        } else {
            parts.append("Connected")
        }
        if let config = appState.activeConfig {
            parts.append(config.name)
        }
        if appState.selectedTable != nil {
            parts.append(appState.currentDatabase)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Table Content Area

struct TableContentArea: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        
        VStack(spacing: 0) {
            TableContentHeader(tab: $state.activeTab)

            if appState.showFilterBar && appState.activeTab == .content {
                FilterBar()
            }
            if appState.hasActiveFilters && appState.activeTab == .content {
                ActiveFiltersBar()
            }

            switch appState.activeTab {
            case .content:
                contentView
            case .structure:
                if let table = appState.selectedTable {
                    TableStructureView(table: table)
                        .id(table.id) // Forces view recreation and .task re-execution when table changes
                }
            case .ddl:
                if let table = appState.selectedTable {
                    DDLView(table: table)
                        .id(table.id)
                }
            }

            BottomBar(tab: $state.activeTab)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if appState.isLoadingData && appState.queryResult.rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.queryResult.rows.isEmpty && !appState.isLoadingData {
            if appState.hasActiveFilters {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No rows match the current filters.")
                } actions: {
                    Button("Clear Filters") {
                        Task { await appState.clearAllFilters() }
                    }
                }
            } else {
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "tablecells.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                    }
                    
                    VStack(spacing: 8) {
                        Text("No Data Available")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        Text("This table is empty. Insert a row to get started.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    Button {
                        appState.insertNewRow()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Insert Row")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            DataGridView()
        }
    }
}

// MARK: - Table Content Header

private struct TableContentHeader: View {
    @Binding var tab: ContentTab
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 10) {
            if let table = appState.selectedTable {
                HStack(spacing: 6) {
                    Image(systemName: table.type.icon)
                        .font(.system(size: 11))
                        .foregroundColor(table.type == .view ? .secondary : .accentColor)
                    Text(table.schema)
                        .foregroundStyle(.tertiary)
                    Text("›").foregroundStyle(.quaternary)
                    Text(table.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
            }

            Spacer()

            tabSegments
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(GlintDesign.panelBackground)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var tabSegments: some View {
        HStack(spacing: 1) {
            ForEach(ContentTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.system(size: 11, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(tab == t ? GlintDesign.quietAccent : .clear, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(GlintDesign.appBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(GlintDesign.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Bottom Bar

private struct BottomBar: View {
    @Binding var tab: ContentTab
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            if tab == .content {
                filterToggle
                
                HStack(spacing: 6) {
                    Button { appState.insertNewRow() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 28)
                    }
                    .buttonStyle(.plain)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.2), lineWidth: 1))
                    .help("Insert New Row")
                    
                    Button { Task { await appState.deleteSelectedRows() } } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 28)
                    }
                    .buttonStyle(.plain)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.2), lineWidth: 1))
                    .disabled(appState.selectedRowIds.isEmpty)
                    .opacity(appState.selectedRowIds.isEmpty ? 0.4 : 1.0)
                    .help("Delete Selected Row(s)")
                }
            }

            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if appState.hasPendingEdits {
                editControls
            }

            if tab == .content && appState.queryResult.totalPages > 1 {
                pagination
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var statusText: String {
        if appState.isLoadingData { return "Loading…" }
        if appState.isLoadingSchema { return "Loading schema…" }
        if appState.queryResult.totalCount > 0 {
            return "\(appState.queryResult.totalCount) rows · \(String(format: "%.0f", appState.queryResult.executionTimeMs)) ms"
        }
        return appState.statusMessage
    }

    private var editControls: some View {
        HStack(spacing: 6) {
            Button("Discard") { appState.discardEdits() }
                .controlSize(.small)

            let saveText = appState.pendingEdits.isEmpty && !appState.newRowIds.isEmpty 
                ? "Save New Row"
                : "Save \(appState.pendingEdits.count) Change\(appState.pendingEdits.count == 1 ? "" : "s")"

            Button(saveText) {
                Task { await appState.commitEdits() }
            }
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var filterToggle: some View {
        let active = appState.showFilterBar || appState.hasActiveFilters
        return Button { appState.showFilterBar.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .bold))
                Text("Filter")
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? .white : .primary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(active ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(active ? .clear : Color.gray.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var pagination: some View {
        HStack(spacing: 12) {
            Button { Task { await appState.previousPage() } } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(appState.currentPage <= 1 || appState.hasPendingEdits)
            .opacity(appState.currentPage <= 1 || appState.hasPendingEdits ? 0.4 : 1)

            Text("\(appState.currentPage) / \(appState.queryResult.totalPages)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button { Task { await appState.nextPage() } } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.queryResult.hasMore || appState.hasPendingEdits)
            .opacity(!appState.queryResult.hasMore || appState.hasPendingEdits ? 0.4 : 1)
        }
    }
}



// MARK: - Prompts

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            if let iconPath = Bundle.module.path(forResource: "AppIcon", ofType: "png"),
               let nsImage = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "tablecells")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
            }

            Text("Glint Database Client")
                .font(.system(size: 24, weight: .semibold))
                
            Text("By Nas Abdulrasaq")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(appState.savedConnections.isEmpty
                 ? "Add a connection to get started."
                 : "Choose a connection from the sidebar.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Button("New Connection") {
                appState.showConnectionSheet = true
            }
            .controlSize(.large)
            .padding(.top, 4)

            Spacer()
            
            VStack(spacing: 4) {
                Text("Built by Nas")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Link("github.com/nosisky", destination: URL(string: "https://github.com/nosisky")!)
                    .font(.system(size: 11))
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlintDesign.appBackground)
    }
}

struct SavedConnectionRow: View {
    let config: ConnectionConfig
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var password = ""
    @State private var showPasswordPrompt = false
    @State private var showDeleteConfirmation = false
    @State private var isConnecting = false
    @State private var connectError: String?

    var body: some View {
        HStack(spacing: 4) {
            Button { promptForPassword() } label: {
                connectionLabel
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            if isHovered {
                if isConnecting {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 22, height: 22)
                } else {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Connection")
                }
            }
        }
        .padding(.trailing, isHovered ? 6 : 0)
        .background(isHovered ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Delete Connection", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .sheet(isPresented: $showPasswordPrompt) {
            PasswordPromptSheet(
                connectionName: config.name,
                host: "\(config.host):\(config.port)/\(config.database)",
                error: connectError,
                onConnect: { pw in
                    password = pw
                    showPasswordPrompt = false
                    connectWithPassword(pw)
                },
                onCancel: {
                    password = ""
                    connectError = nil
                    showPasswordPrompt = false
                }
            )
        }
        .alert("Delete Connection?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                appState.removeConnection(config)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(config.name) and its saved password from this Mac.")
        }
    }

    private var connectionLabel: some View {
        HStack(spacing: 8) {
            if config.colorTag != .none {
                Circle()
                    .fill(GlintDesign.tagColor(config.colorTag))
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(config.name).font(.system(size: 13))
                Text("\(config.host):\(config.port)/\(config.database)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isConnecting {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func promptForPassword() {
        if let saved = try? KeychainService.readPassword(account: config.keychainAccount) {
            connectWithPassword(saved, deleteOnFailure: true)
        } else {
            password = ""
            connectError = nil
            showPasswordPrompt = true
        }
    }

    private func connectWithPassword(_ password: String, deleteOnFailure: Bool = false) {
        isConnecting = true
        connectError = nil
        Task {
            let success = await appState.connect(config: config, password: password)
            if success {
                self.password = ""
                connectError = nil
            } else {
                if deleteOnFailure {
                    try? KeychainService.deletePassword(account: config.keychainAccount)
                }
                self.password = ""
                connectError = appState.connectionError ?? "Connection failed"
                showPasswordPrompt = true
            }
            isConnecting = false
        }
    }
}

// MARK: - Password Prompt Sheet

/// Separate sheet for password entry — avoids the .alert SecureField focus bug on macOS.
private struct PasswordPromptSheet: View {
    let connectionName: String
    let host: String
    let error: String?
    let onConnect: (String) -> Void
    let onCancel: () -> Void
    @State private var password = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                Text("Enter Password")
                    .font(.system(size: 14, weight: .semibold))

                Text(connectionName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(host)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            NativeSecureField(text: $password, placeholder: "Password")
                .frame(height: 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") { onConnect(password) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SelectTablePrompt: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("Select a table from the sidebar")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Glint Workspace by Nas")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlintDesign.appBackground)
    }
}
