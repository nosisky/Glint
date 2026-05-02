//
//  ConnectionSheet.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// Connection form — simple, native-feeling.
struct ConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var config = ConnectionConfig()
    @State private var password = ""
    @State private var portString = "5432"
    @State private var isTesting = false
    @State private var isConnecting = false
    @State private var testResult: String?
    @State private var testSuccess = false

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
            HStack {
                Text("New Connection")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Grid(alignment: .trailing, verticalSpacing: 8) {
                GridRow {
                    Text("Name").gridColumnAlignment(.trailing)
                    NativeTextField(text: $config.name, placeholder: "My Database")
                        .frame(height: 22)
                }
                GridRow {
                    Text("Host")
                    NativeTextField(text: $config.host, placeholder: "localhost")
                        .frame(height: 22)
                }
                GridRow {
                    Text("Port")
                    NativeTextField(text: $portString, placeholder: "5432")
                        .frame(height: 22)
                        .frame(width: 100)
                        .gridColumnAlignment(.leading)
                        .onChange(of: portString) { _, v in config.port = Int(v) ?? 5432 }
                }
                GridRow {
                    Text("Database")
                    NativeTextField(text: $config.database, placeholder: "postgres")
                        .frame(height: 22)
                }

                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                    .padding(.vertical, 4)

                GridRow {
                    Text("User")
                    NativeTextField(text: $config.user, placeholder: "postgres")
                        .frame(height: 22)
                }
                GridRow {
                    Text("Password")
                    NativeSecureField(text: $password, placeholder: "")
                        .frame(height: 22)
                }

                GridRow {
                    Text("")
                    Toggle("Use SSL", isOn: $config.useSSL)
                        .toggleStyle(.checkbox)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if let result = testResult {
                HStack(spacing: 6) {
                    Image(systemName: testSuccess ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(testSuccess ? .green : .red)
                    Text(result)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Test Connection") { testConnection() }
                    .disabled(!canSubmit)

                if isTesting || isConnecting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Connect") { saveAndConnect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { portString = "\(config.port)" }
    }

    private func testConnection() {
        guard canSubmit else { return }
        isTesting = true
        testResult = nil
        Task {
            do {
                let conn = PostgresConnection(config: sanitizedConfig(), password: password)
                try await conn.connect()
                await conn.disconnect()
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
                dismiss()
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
