//
//  SidebarView.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

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

private enum SidebarTab: String, CaseIterable {
    case tables = "Tables"
    case functions = "Functions"
}

// MARK: - Connected

private struct ConnectedSidebar: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var sidebarTab: SidebarTab = .tables

    private var visibleSchemas: [DatabaseSchemaInfo] {
        if searchText.isEmpty {
            return appState.schemas.filter { sidebarTab == .tables ? !$0.tables.isEmpty : !$0.functions.isEmpty }
        }
        let needle = searchText
        return appState.schemas.compactMap { schema in
            if sidebarTab == .tables {
                let filtered = schema.tables.filter { $0.name.localizedCaseInsensitiveContains(needle) }
                if filtered.isEmpty { return nil }
                return DatabaseSchemaInfo(name: schema.name, tables: filtered, functions: schema.functions)
            } else {
                let filtered = schema.functions.filter { $0.name.localizedCaseInsensitiveContains(needle) }
                if filtered.isEmpty { return nil }
                return DatabaseSchemaInfo(name: schema.name, tables: schema.tables, functions: filtered)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            connectionHeader

            List(selection: Binding<String?>(
                get: { sidebarTab == .tables ? appState.selectedTable?.id : appState.selectedFunction?.id },
                set: { id in
                    guard let id else { return }
                    // Close query editor when navigating to a table/function
                    if appState.isQueryEditorOpen { appState.isQueryEditorOpen = false }
                    if sidebarTab == .tables {
                        if id == appState.selectedTable?.id { return }
                        let allTables = appState.schemas.flatMap(\.tables)
                        if let match = allTables.first(where: { $0.id == id }) {
                            Task { await appState.selectTable(match) }
                        }
                    } else {
                        if id == appState.selectedFunction?.id { return }
                        let allFunctions = appState.schemas.flatMap(\.functions)
                        if let match = allFunctions.first(where: { $0.id == id }) {
                            appState.selectFunction(match)
                        }
                    }
                }
            )) {
                let schemas = visibleSchemas

                ForEach(schemas) { schema in
                    if schema.name == "public" {
                        if sidebarTab == .tables {
                            tableList(schema.tables)
                        } else {
                            functionList(schema.functions)
                        }
                    } else {
                        SchemaDisclosureGroup(schema: schema) {
                            if sidebarTab == .tables {
                                tableList(schema.tables)
                            } else {
                                functionList(schema.functions)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search tables")
        }
        .overlay {
            if appState.isLoadingSchema && appState.schemas.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.thinMaterial)
            }
        }
    }

    private var connectionHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.isConnecting ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)

                    Text(appState.activeConfig?.name ?? "Local")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        Task { await appState.loadSchema() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Schema")

                    Button {
                        Task { await appState.disconnect() }
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Disconnect")
                }

                if appState.databases.count > 1 {
                    @Bindable var state = appState
                    Picker("", selection: $state.currentDatabase) {
                        ForEach(appState.databases, id: \.self) { db in
                            Text(db).tag(db)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .labelsHidden()
                    .onChange(of: appState.currentDatabase) { oldValue, newValue in
                        guard newValue != oldValue else { return }
                        Task { await appState.switchDatabase(newValue) }
                    }
                } else {
                    Text(appState.currentDatabase)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(GlintDesign.panelBackground)

            Picker("", selection: $sidebarTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .background(GlintDesign.panelBackground)

            Divider()
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
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .tag(table.id)
            .contextMenu {
                Button("Open Contents") {
                    Task {
                        await appState.selectTable(table)
                        appState.activeTab = .content
                    }
                }
                
                Button("Open Structure") {
                    Task {
                        await appState.selectTable(table)
                        appState.activeTab = .structure
                    }
                }
                
                Button("Open DDL") {
                    Task {
                        await appState.selectTable(table)
                        appState.activeTab = .ddl
                    }
                }
                
                Divider()
                
                Button("Copy Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(table.name, forType: .string)
                }
                
                Button("Copy Name with Schema") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(table.schema).\(table.name)", forType: .string)
                }
                
                Divider()
                
                Menu("Export") {
                    Button("Export as CSV...") {
                        Task {
                            await appState.selectTable(table)
                            await appState.exportTableAsCSV()
                        }
                    }
                    Button("Export as JSON...") {
                        Task {
                            await appState.selectTable(table)
                            await appState.exportTableAsJSON()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func functionList(_ functions: [FunctionInfo]) -> some View {
        let noExtension = functions.filter { $0.extensionName == nil }
        let withExtension = Dictionary(grouping: functions.filter { $0.extensionName != nil }, by: { $0.extensionName! })
        
        ForEach(noExtension) { function in
            functionRow(function)
        }
        
        let sortedExtensions = withExtension.keys.sorted()
        ForEach(sortedExtensions, id: \.self) { extName in
            ExtensionDisclosureGroup(extensionName: extName) {
                ForEach(withExtension[extName]!) { function in
                    functionRow(function)
                }
            }
        }
    }

    @ViewBuilder
    private func functionRow(_ function: FunctionInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "f.cursive.circle")
                .font(.system(size: 10))
                .foregroundColor(.accentColor)
                .frame(width: 14)

            Text(function.name)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .tag(function.id)
        .contextMenu {
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(function.name, forType: .string)
            }
            Button("Copy Signature") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(function.name)(\(function.arguments))", forType: .string)
            }
        }
    }
}

// MARK: - Schema Disclosure Group

private struct SchemaDisclosureGroup<Content: View>: View {
    let schema: DatabaseSchemaInfo
    let content: Content
    
    @State private var isExpanded: Bool = false

    init(schema: DatabaseSchemaInfo, @ViewBuilder content: () -> Content) {
        self.schema = schema
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill").foregroundStyle(.secondary)
                Text(schema.name).font(.system(size: 12, weight: .semibold))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { isExpanded.toggle() }
            }
        }
        .tint(.secondary)
    }
}

private struct ExtensionDisclosureGroup<Content: View>: View {
    let extensionName: String
    let content: Content
    
    @State private var isExpanded: Bool = false

    init(extensionName: String, @ViewBuilder content: () -> Content) {
        self.extensionName = extensionName
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill").foregroundStyle(.secondary)
                Text(extensionName).font(.system(size: 12, weight: .semibold))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { isExpanded.toggle() }
            }
        }
        .tint(.secondary)
    }
}

// MARK: - Disconnected

private struct DisconnectedSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Connections")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    appState.showConnectionSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("New Connection")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(GlintDesign.panelBackground)
            .overlay(alignment: .bottom) { Divider() }

            List {
                if appState.savedConnections.isEmpty {
                    VStack(spacing: 6) {
                        Text("No saved connections")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Button("New Connection") {
                            appState.showConnectionSheet = true
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                } else {
                    Section("Saved") {
                        ForEach(appState.savedConnections) { config in
                            SavedConnectionRow(config: config)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}
