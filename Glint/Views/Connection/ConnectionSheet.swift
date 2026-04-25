import SwiftUI

/// New/Edit connection form sheet.
/// Uses manual layout instead of Form to avoid macOS focus issues in sheets.
struct ConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var config = ConnectionConfig()
    @State private var password = ""
    @State private var portString = "5432"
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

            // Form fields (manual layout for reliable text editing on macOS)
            ScrollView {
                VStack(spacing: GlintDesign.spacingXL) {
                    // Connection section
                    FormSection(title: "Connection") {
                        FormField(label: "Name") {
                            NativeTextField(text: $config.name, placeholder: "My Database")
                                .frame(height: 24)
                        }
                        FormField(label: "Host") {
                            NativeTextField(text: $config.host, placeholder: "localhost")
                                .frame(height: 24)
                        }
                        FormField(label: "Port") {
                            NativeTextField(text: $portString, placeholder: "5432")
                                .frame(height: 24)
                                .onChange(of: portString) { _, newValue in
                                    config.port = Int(newValue) ?? 5432
                                }
                        }
                        FormField(label: "Database") {
                            NativeTextField(text: $config.database, placeholder: "postgres")
                                .frame(height: 24)
                        }
                    }

                    // Authentication section
                    FormSection(title: "Authentication") {
                        FormField(label: "User") {
                            NativeTextField(text: $config.user, placeholder: "postgres")
                                .frame(height: 24)
                        }
                        FormField(label: "Password") {
                            NativeSecureField(text: $password, placeholder: "Password")
                                .frame(height: 24)
                        }
                    }

                    // Options section
                    FormSection(title: "Options") {
                        FormField(label: "SSL") {
                            Toggle("Use SSL", isOn: $config.useSSL)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        FormField(label: "Color Tag") {
                            Picker("", selection: $config.colorTag) {
                                ForEach(ColorTag.allCases, id: \.self) { tag in
                                    HStack(spacing: 6) {
                                        if tag != .none {
                                            Circle()
                                                .fill(GlintDesign.tagColor(tag))
                                                .frame(width: 8, height: 8)
                                        }
                                        Text(tag.displayName)
                                    }
                                    .tag(tag)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                    }
                }
                .padding(GlintDesign.spacingLG)
            }

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
                .padding(.bottom, GlintDesign.spacingSM)
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
        .frame(width: 480, height: 560)
        .animation(GlintDesign.smooth, value: testResult != nil)
        .onAppear {
            portString = "\(config.port)"
        }
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

// MARK: - Form Components

/// A labeled section with a title and grouped content.
private struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: GlintDesign.spacingSM) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: GlintDesign.spacingSM) {
                content
            }
            .padding(GlintDesign.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: GlintDesign.cornerRadiusLG)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: GlintDesign.cornerRadiusLG)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }
}

/// A single form row with a label and control.
private struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .trailing)

            content
        }
    }
}
