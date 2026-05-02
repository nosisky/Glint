//
//  GlintColors.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

enum GlintDesign {
    static let appBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor).opacity(0.55)
    static let quietAccent = Color.accentColor.opacity(0.12)
    static let pendingEdit = Color.orange
    static let pendingEditSubtle = Color.orange.opacity(0.12)
    static let nullText = Color(nsColor: .placeholderTextColor)

    /// Safe alternating row tint; falls back to controlBackgroundColor.
    static let alternatingRow: Color = {
        let colors = NSColor.alternatingContentBackgroundColors
        return Color(nsColor: colors.indices.contains(1) ? colors[1] : .controlBackgroundColor)
    }()

    static let rowHeight: CGFloat = 24
    static let headerHeight: CGFloat = 28
    static let defaultColumnWidth: CGFloat = 150

    static func tagColor(_ tag: ColorTag) -> Color {
        switch tag {
        case .none: .clear
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}
