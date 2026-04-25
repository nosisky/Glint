import SwiftUI

/// Design tokens for Glint — colors, spacing, typography constants.
/// Strict adherence to Apple HIG with a premium accent palette.
enum GlintDesign {

    // MARK: - Colors

    /// Signature accent — warm gold for pending edits, selected states, and branding.
    static let gold = Color(red: 0.831, green: 0.659, blue: 0.263)
    static let goldSubtle = Color(red: 0.831, green: 0.659, blue: 0.263, opacity: 0.15)
    static let goldBorder = Color(red: 0.831, green: 0.659, blue: 0.263, opacity: 0.5)

    /// Semantic colors (system-native for automatic dark/light mode).
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let selectedContent = Color(nsColor: .selectedContentBackgroundColor)
    static let alternatingRow = Color(nsColor: .alternatingContentBackgroundColors[1])

    /// Status colors
    static let success = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.15)
    static let error = Color(red: 0.9, green: 0.25, blue: 0.2)
    static let nullValue = Color(nsColor: .placeholderTextColor)

    // MARK: - Spacing (8pt grid, HIG compliant)

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32

    // MARK: - Grid

    static let rowHeight: CGFloat = 28
    static let headerHeight: CGFloat = 32
    static let minColumnWidth: CGFloat = 80
    static let defaultColumnWidth: CGFloat = 160
    static let maxColumnWidth: CGFloat = 500

    // MARK: - Corner Radius

    static let cornerRadiusSM: CGFloat = 4
    static let cornerRadiusMD: CGFloat = 6
    static let cornerRadiusLG: CGFloat = 10

    // MARK: - Animations

    static let snappy = Animation.snappy(duration: 0.2)
    static let smooth = Animation.smooth(duration: 0.3)
    static let spring = Animation.spring(duration: 0.35, bounce: 0.15)

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

// MARK: - View Modifiers

struct GlintCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: GlintDesign.cornerRadiusLG))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

struct GlintButtonStyle: ButtonStyle {
    let isPrimary: Bool

    init(isPrimary: Bool = false) {
        self.isPrimary = isPrimary
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: isPrimary ? .semibold : .regular))
            .padding(.horizontal, GlintDesign.spacingMD)
            .padding(.vertical, GlintDesign.spacingSM)
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: GlintDesign.cornerRadiusMD)
                        .fill(GlintDesign.gold)
                } else {
                    RoundedRectangle(cornerRadius: GlintDesign.cornerRadiusMD)
                        .fill(.regularMaterial)
                }
            }
            .foregroundStyle(isPrimary ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(GlintDesign.snappy, value: configuration.isPressed)
    }
}

extension View {
    func glintCard() -> some View {
        modifier(GlintCardStyle())
    }
}
