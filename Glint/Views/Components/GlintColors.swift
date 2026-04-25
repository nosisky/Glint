import SwiftUI

enum GlintDesign {
    static let pendingEdit = Color.orange
    static let pendingEditSubtle = Color.orange.opacity(0.12)
    static let nullText = Color(nsColor: .placeholderTextColor)

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
