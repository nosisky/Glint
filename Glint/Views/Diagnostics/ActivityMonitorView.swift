//
//  ActivityMonitorView.swift
//  Glint
//

import SwiftUI

struct ActivityMonitorView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("glint.activityRefreshRate") private var refreshRate = 3.0
    
    // Auto-refresh timer
    let timer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
    
    // Selection and Actions
    @State private var sortOrder = [KeyPathComparator(\PgBackendActivity.sortDuration, order: .reverse)]
    @State private var selectedPid: PgBackendActivity.ID?
    
    // Safety Alerts
    @State private var backendToCancel: Int?
    @State private var backendToTerminate: Int?
    @State private var showCancelAlert = false
    @State private var showTerminateAlert = false
    
    var sortedActivities: [PgBackendActivity] {
        appState.backendActivities.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            
            VSplitView {
                activeConnectionsTable
                queryDetailPanel
            }
        }
        .alert("Cancel Query?", isPresented: $showCancelAlert, presenting: backendToCancel) { pid in
            Button("Cancel Query", role: .destructive) {
                Task { await appState.cancelBackend(pid: pid) }
            }
            Button("Keep Running", role: .cancel) { }
        } message: { pid in
            Text("Are you sure you want to gracefully cancel the query running on PID \(pid)? The connection will remain open.")
        }
        .alert("Terminate Connection?", isPresented: $showTerminateAlert, presenting: backendToTerminate) { pid in
            Button("Terminate", role: .destructive) {
                Task { await appState.terminateBackend(pid: pid) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { pid in
            Text("Are you sure you want to forcefully terminate the connection for PID \(pid)? This is a destructive action.")
        }
        .onAppear {
            Task { await appState.fetchActivity() }
        }
        .onReceive(timer) { _ in
            Task { await appState.fetchActivity() }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(.accentColor)
            Text("Activity Monitor")
                .font(.headline)
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .opacity(0.8)
                Text("Live")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.1))
            .cornerRadius(4)
            
            Button {
                Task { await appState.fetchActivity() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh Now")
        }
        .padding()
        .background(GlintDesign.panelBackground)
    }
    
    private var activeConnectionsTable: some View {
        Table(sortedActivities, selection: $selectedPid, sortOrder: $sortOrder) {
            TableColumn("PID", value: \.pid) { activity in
                Text("\(activity.pid)")
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 60, max: 80)
            
            TableColumn("State", value: \.state) { activity in
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor(for: activity.state))
                        .frame(width: 6, height: 6)
                    Text(activity.state)
                }
            }
            .width(min: 80, ideal: 100, max: 150)
            
            TableColumn("Duration", value: \.sortDuration) { activity in
                Text(activity.formattedDuration)
                    .monospacedDigit()
                    .foregroundColor(durationColor(for: activity.duration))
            }
            .width(min: 60, ideal: 80, max: 100)
            
            TableColumn("User", value: \.user)
                .width(min: 60, ideal: 100, max: 150)
            
            TableColumn("Wait Event", value: \.waitEvent)
                .width(min: 80, ideal: 120, max: 200)
            
            TableColumn("Query", value: \.query) { activity in
                Text(activity.query)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .contextMenu(forSelectionType: PgBackendActivity.ID.self) { items in
            if let pid = items.first {
                Button(role: .destructive) {
                    backendToCancel = pid
                    showCancelAlert = true
                } label: {
                    Label("Cancel Query", systemImage: "xmark.octagon")
                }
                
                Button(role: .destructive) {
                    backendToTerminate = pid
                    showTerminateAlert = true
                } label: {
                    Label("Terminate Connection", systemImage: "bolt.horizontal.circle.fill")
                }
                
                Divider()
                
                Button("Copy Query") {
                    if let activity = appState.backendActivities.first(where: { $0.pid == pid }) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(activity.query, forType: .string)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var queryDetailPanel: some View {
        if let selectedPid = selectedPid,
           let selectedActivity = appState.backendActivities.first(where: { $0.pid == selectedPid }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Query Details (PID: \(selectedPid))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Copy Full Query") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selectedActivity.query, forType: .string)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(GlintDesign.panelBackground)
                
                Divider()
                
                TextEditor(text: .constant(selectedActivity.query))
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .padding(8)
            }
            .frame(minHeight: 150)
        } else {
            // Empty state for detail panel
            VStack {
                Text("Select a connection to view its query")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func stateColor(for state: String) -> Color {
        switch state.lowercased() {
        case "active": return .green
        case "idle": return .gray
        case "idle in transaction", "idle in transaction (aborted)": return .orange
        case "fastpath function call": return .blue
        default: return .secondary
        }
    }
    
    private func durationColor(for duration: TimeInterval?) -> Color {
        guard let duration = duration else { return .primary }
        if duration > 10.0 { return .red }
        if duration > 3.0 { return .orange }
        return .primary
    }
}
