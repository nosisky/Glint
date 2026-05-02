//
//  StatusBarView.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// Lightweight status indicator. Not used in main toolbar anymore
/// (status is inline in ContentView). Kept for potential use in other contexts.
struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 6) {
            if appState.isConnected {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
            Text(appState.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
