import SwiftUI
import AppKit

class GlintAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct GlintApp: App {
    @NSApplicationDelegateAdaptor(GlintAppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Glint") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") { appState.showConnectionSheet = true }
                    .keyboardShortcut("n", modifiers: [.command])
                Divider()
                Button("New Tab") { appState.addNewTab() }
                    .keyboardShortcut("t", modifiers: [.command])
                    .disabled(!appState.isConnected)
                Button("Close Tab") {
                    if let id = appState.activeWorkspaceTabId {
                        appState.closeTab(id: id)
                    }
                }
                    .keyboardShortcut("w", modifiers: [.command])
                    .disabled(!appState.isConnected)
                Divider()
                Button("Refresh Schema") { Task { await appState.loadSchema() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!appState.isConnected)
            }

            CommandGroup(after: .toolbar) {
                Button("Open SQL Console") { appState.showConsole = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(!appState.isConnected)
                Divider()
                Button("Clear All Filters") { Task { await appState.clearAllFilters() } }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .disabled(!appState.hasActiveFilters)
            }

            CommandGroup(after: .undoRedo) {
                if appState.hasPendingEdits {
                    Divider()
                    Button("Commit Changes") { Task { await appState.commitEdits() } }
                        .keyboardShortcut(.return, modifiers: [.command])
                    Button("Discard Changes") { appState.discardEdits() }
                        .keyboardShortcut(.delete, modifiers: [.command, .shift])
                }
            }

            CommandMenu("Database") {
                if appState.isConnected {
                    Button("Disconnect") { Task { await appState.disconnect() } }
                    Divider()
                    Button("Next Page") { Task { await appState.nextPage() } }
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                        .disabled(!appState.queryResult.hasMore)
                    Button("Previous Page") { Task { await appState.previousPage() } }
                        .keyboardShortcut(.leftArrow, modifiers: [.command])
                        .disabled(appState.currentPage <= 1)
                } else {
                    Button("Connect…") { appState.showConnectionSheet = true }
                }
            }
        }

        Window("SQL Console", id: "sql-console") {
            RawConsoleView()
                .environment(appState)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 800, height: 500)
        .windowStyle(.titleBar)

        Settings {
            SettingsView().frame(width: 450, height: 300)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("glint.pageSize") private var pageSize = 200
    @AppStorage("glint.theme") private var theme = "system"

    var body: some View {
        TabView {
            Form {
                Section("Data Grid") {
                    Picker("Rows per page", selection: $pageSize) {
                        Text("100").tag(100)
                        Text("200").tag(200)
                        Text("500").tag(500)
                        Text("1000").tag(1000)
                    }
                }
                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }
        }
    }
}
