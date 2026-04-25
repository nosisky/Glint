import SwiftUI

/// Minimal design tokens for Glint.
/// Uses native macOS system colors wherever possible.
/// Only defines values that can't be derived from the system.
enum GlintDesign {

    // MARK: - Accent

    /// Subtle warm accent for pending edits only.
    static let pendingEdit = Color.orange
    static let pendingEditSubtle = Color.orange.opacity(0.12)

    /// NULL value styling
    static let nullText = Color(nsColor: .placeholderTextColor)

    // MARK: - Grid Metrics

    static let rowHeight: CGFloat = 24
    static let headerHeight: CGFloat = 28
    static let defaultColumnWidth: CGFloat = 150

    // MARK: - Tag Colors

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
