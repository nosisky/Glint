import SwiftUI

/// New/Edit connection form sheet.
struct ConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var config = ConnectionConfig()
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Connection")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(GlintDesign.spacingLG)

            Divider()

            // Form
            Form {
                Section("Connection") {
                    TextField("Name", text: $config.name)
                    TextField("Host", text: $config.host)
                    TextField("Port", value: $config.port, format: .number)
                    TextField("Database", text: $config.database)
                }

                Section("Authentication") {
                    TextField("User", text: $config.user)
                    SecureField("Password", text: $password)
                }

                Section("Options") {
                    Toggle("Use SSL", isOn: $config.useSSL)
                    Picker("Color Tag", selection: $config.colorTag) {
                        ForEach(ColorTag.allCases, id: \.self) { tag in
                            HStack {
                                if tag != .none {
                                    Circle().fill(GlintDesign.tagColor(tag)).frame(width: 8, height: 8)
                                }
                                Text(tag.displayName)
                            }
                            .tag(tag)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            // Test result
            if let result = testResult {
                HStack(spacing: GlintDesign.spacingSM) {
                    switch result {
                    case .success(let msg):
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(GlintDesign.success)
                        Text(msg).font(.system(size: 12)).foregroundStyle(GlintDesign.success)
                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(GlintDesign.error)
                        Text(msg).font(.system(size: 12)).foregroundStyle(GlintDesign.error).lineLimit(2)
                    }
                }
                .padding(.horizontal, GlintDesign.spacingLG)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Divider()

            // Actions
            HStack {
                Button("Test Connection") { testConnection() }
                    .buttonStyle(GlintButtonStyle())
                    .disabled(isTesting)

                if isTesting {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save & Connect") { saveAndConnect() }
                    .buttonStyle(GlintButtonStyle(isPrimary: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(GlintDesign.spacingLG)
        }
        .frame(width: 460, height: 520)
        .animation(GlintDesign.smooth, value: testResult != nil)
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let conn = PostgresConnection(config: config, password: password)
                try await conn.connect()
                await conn.disconnect()
                testResult = .success("Connection successful!")
            } catch {
                testResult = .failure(error.localizedDescription)
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
