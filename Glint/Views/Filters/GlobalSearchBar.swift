//
//  GlobalSearchBar.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// Toolbar search field.
struct GlobalSearchBar: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    var body: some View {
        TextField("Filter…", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            .onSubmit {
                Task { await appState.performGlobalSearch(searchText) }
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    Task { await appState.performGlobalSearch("") }
                }
            }
    }
}
