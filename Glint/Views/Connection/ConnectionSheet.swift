//
//  ConnectionSheet.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// Connection form — simple, native-feeling, advanced.
struct ConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var config = ConnectionConfig()
    @State private var password = ""
    @State private var portString = "5432"
    @State private var uriInput = ""
    
    // UI State
    @State private var isTesting = false
    @State private var isConnecting = false
    @State private var testResult: String?
    @State private var testSuccess = false
    @State private var showSSHTunnel = false
    @State private var showStartupQuery = false
    @State private var showPreConnectScript = false

    private var canSubmit: Bool {
        !config.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !config.database.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !config.user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        Int(portString) != nil &&
        !isTesting &&
        !isConnecting
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Connection")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Glint by Nas")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    
                    // URI Auto-Fill
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                        NativeTextField(text: $uriInput, placeholder: "Paste postgresql:// URI here to auto-fill...")
                            .frame(height: 24)
                            .onChange(of: uriInput) { _, newValue in
                                if let extractedPassword = config.apply(fromURI: newValue) {
                                    password = extractedPassword
                                }
                                portString = "\(config.port)"
                                uriInput = "" // Clear after applying
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .padding(.top, 4)
                    
                    // Main Grid
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Nickname").frame(maxWidth: 80, alignment: .trailing).foregroundColor(.secondary)
                            NativeTextField(text: $config.name, placeholder: "Untitled Server")
                                .frame(height: 22)
                        }
                        
                        GridRow {
                            Text("Color").frame(maxWidth: 80, alignment: .trailing).foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(ColorTag.allCases, id: \.self) { tag in
                                    Circle()
                                        .fill(colorForTag(tag))
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            Circle().stroke(Color.primary.opacity(config.colorTag == tag ? 0.8 : 0.1), lineWidth: 2)
                                        )
                                        .onTapGesture { config.colorTag = tag }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Divider().gridCellUnsizedAxes(.horizontal).padding(.vertical, 4)
                        
                        GridRow {
                            Text("Host").frame(maxWidth: 80, alignment: .trailing).foregroundColor(.secondary)
                            HStack {
                                NativeTextField(text: $config.host, placeholder: "localhost")
                                    .frame(height: 22)
                                Text("Port").foregroundColor(.secondary).padding(.leading, 8)
                                NativeTextField(text: $portString, placeholder: "5432")
                                    .frame(width: 60, height: 22)
                                    .onChange(of: portString) { _, v in config.port = Int(v) ?? 5432 }
                            }
                        }
                        
                        GridRow {
                            Text("Database").frame(maxWidth: 80, alignment: .trailing).foregroundColor(.secondary)
                            NativeTextField(text: $config.database, placeholder: "postgres")
                                .frame(height: 22)
                        }
                        
                        GridRow {
                            Text("User").frame(maxWidth: 80, alignment: .trailing).foregroundColor(.secondary)
                            NativeTextField(text: $config.user, placeholder: "postgres")
                                .frame(height: 22)
                        }
                        
                        GridRow {
                            Text("Password").frame(maxWidth: 80, alignment: .trailing).foregroundColor(.secondary)
                            NativeSecureField(text: $password, placeholder: "")
                                .frame(height: 22)
                        }
                        
                        GridRow {
                            Text("SSL Mode").frame(maxWidth: 80, alignment: .trailing).foregroundColor(.secondary)
                            Picker("", selection: $config.sslMode) {
                                ForEach(SSLMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }
                    .font(.system(size: 13))

                    Divider()

                    // Options (mTLS)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Options")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                        
                        FilePicker(title: "Server CA", path: $config.serverCACertPath)
                        FilePicker(title: "Client Cert", path: $config.clientCertPath)
                        FilePicker(title: "Client Key", path: $config.clientKeyPath)
                    }

                    Divider()

                    // Advanced Toggles
                    VStack(alignment: .leading, spacing: 16) {
                        // SSH Tunnel
                        ToggleSection(
                            isOn: $showSSHTunnel,
                            title: "Connect via SSH Tunnel",
                            subtitle: "SSH Tunnels are a secure way to connect to servers behind a firewall"
                        ) {
                            if config.sshTunnel == nil { config.sshTunnel = SSHTunnelConfig() }
                            return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                GridRow {
                                    Text("SSH Host").frame(maxWidth: 80, alignment: .trailing).foregroundColor(.secondary)
                                    NativeTextField(text: Binding(get: { config.sshTunnel?.sshHost ?? "" }, set: { config.sshTunnel?.sshHost = $0 }), placeholder: "bastion.example.com")
                                }
                                GridRow {
                                    Text("SSH User").frame(maxWidth: 80, alignment: .trailing).foregroundColor(.secondary)
                                    NativeTextField(text: Binding(get: { config.sshTunnel?.sshUser ?? "" }, set: { config.sshTunnel?.sshUser = $0 }), placeholder: "ubuntu")
                                }
                            }
                            .font(.system(size: 12))
                            .padding(.leading, 24)
                            .padding(.top, 4)
                        } onToggleOff: {
                            config.sshTunnel = nil
                        }

                        // Startup Query
                        ToggleSection(
                            isOn: $showStartupQuery,
                            title: "Startup Query",
                            subtitle: "Automatically execute SQL commands after connecting to the server"
                        ) {
                            TextEditor(text: Binding(get: { config.startupQuery ?? "" }, set: { config.startupQuery = $0 }))
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 60)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                                .padding(.leading, 24)
                                .padding(.top, 4)
                        } onToggleOff: {
                            config.startupQuery = nil
                        }

                        // Pre-Connect Script
                        ToggleSection(
                            isOn: $showPreConnectScript,
                            title: "Pre-Connect Shell Script",
                            subtitle: "Use a script to set connection parameters (e.g., generating IAM tokens)."
                        ) {
                            TextEditor(text: Binding(get: { config.preConnectScript ?? "" }, set: { config.preConnectScript = $0 }))
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 60)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                                .padding(.leading, 24)
                                .padding(.top, 4)
                        } onToggleOff: {
                            config.preConnectScript = nil
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(maxHeight: 550)

            if let result = testResult {
                HStack(spacing: 6) {
                    Image(systemName: testSuccess ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(testSuccess ? .green : .red)
                    Text(result)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            Divider()

            // Toolbar Actions
            HStack(spacing: 12) {
                Button(action: { /* Future: Delete */ }) {
                    Image(systemName: "trash")
                }.buttonStyle(.plain).foregroundColor(.secondary).disabled(true)
                
                Button(action: { /* Future: Export */ }) {
                    Image(systemName: "square.and.arrow.up")
                }.buttonStyle(.plain).foregroundColor(.secondary).disabled(true)

                Spacer()
                
                if isTesting || isConnecting {
                    ProgressView().controlSize(.small).padding(.trailing, 8)
                }

                Button("Test") { testConnection() }
                    .disabled(!canSubmit)
                
                Button("Show Databases") { /* Future implementation */ }
                    .disabled(true)

                Button("Connect") { saveAndConnect() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 500)
        .onAppear {
            portString = "\(config.port)"
            showSSHTunnel = config.sshTunnel != nil
            showStartupQuery = config.startupQuery != nil
            showPreConnectScript = config.preConnectScript != nil
        }
    }

    private func colorForTag(_ tag: ColorTag) -> Color {
        switch tag {
        case .none: return Color(nsColor: .quaternaryLabelColor)
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        }
    }

    private func testConnection() {
        guard canSubmit else { return }
        isTesting = true
        testResult = nil
        Task {
            do {
                let conn = PostgresConnection(config: sanitizedConfig(), password: password)
                try await conn.connect()
                await conn.disconnectAndAwait()
                testResult = "Connection successful"
                testSuccess = true
            } catch {
                testResult = error.localizedDescription
                testSuccess = false
            }
            isTesting = false
        }
    }

    private func saveAndConnect() {
        guard canSubmit else { return }
        let cleanConfig = sanitizedConfig()
        isConnecting = true
        testResult = nil
        Task {
            let success = await appState.connect(config: cleanConfig, password: password)
            if success {
                appState.addConnection(cleanConfig)
                appState.showConnectionSheet = false
            } else {
                testResult = appState.connectionError ?? "Connection failed"
                testSuccess = false
            }
            isConnecting = false
        }
    }

    private func sanitizedConfig() -> ConnectionConfig {
        var clean = config
        clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.host = clean.host.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.database = clean.database.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.user = clean.user.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.port = Int(portString) ?? 5432
        if clean.name.isEmpty {
            clean.name = "\(clean.user)@\(clean.host)"
        }
        return clean
    }
}

/// A helper view to mimic Postico's advanced section toggles
struct ToggleSection<Content: View>: View {
    @Binding var isOn: Bool
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    let onToggleOff: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .onChange(of: isOn) { _, newValue in
                if !newValue { onToggleOff() }
            }
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 24)
            
            if isOn {
                content()
            }
        }
    }
}
