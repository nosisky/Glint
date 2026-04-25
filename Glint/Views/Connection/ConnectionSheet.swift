import SwiftUI

/// Connection form — simple, native-feeling.
struct ConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var config = ConnectionConfig()
    @State private var password = ""
    @State private var portString = "5432"
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("New Connection")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            Divider()

            // Fields
            Grid(alignment: .trailing, verticalSpacing: 10) {
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
            .font(.system(size: 13))
            .padding(20)

            // Test result
            if let result = testResult {
                HStack(spacing: 6) {
                    Image(systemName: testSuccess ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(testSuccess ? .green : .red)
                    Text(result)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            Divider()

            // Actions
            HStack {
                Button("Test Connection") { testConnection() }
                    .disabled(isTesting)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Connect") { saveAndConnect() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { portString = "\(config.port)" }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let conn = PostgresConnection(config: config, password: password)
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
        appState.addConnection(config)
        dismiss()
        Task { await appState.connect(config: config, password: password) }
    }
}
