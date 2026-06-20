import SwiftUI

extension Color {
    // Background hierarchy
    #if canImport(UIKit)
    static let mBgPrimary = Color(.systemBackground)
    static let mBgSecondary = Color(.secondarySystemBackground)
    static let mBgGrouped = Color(.systemGroupedBackground)
    #else
    static let mBgPrimary = Color(.windowBackgroundColor)
    static let mBgSecondary = Color(.controlBackgroundColor)
    static let mBgGrouped = Color(.underPageBackgroundColor)
    #endif

    // Text hierarchy
    #if canImport(UIKit)
    static let mTextPrimary = Color(.label)
    static let mTextSecondary = Color(.secondaryLabel)
    static let mTextTertiary = Color(.tertiaryLabel)
    #else
    static let mTextPrimary = Color(.labelColor)
    static let mTextSecondary = Color(.secondaryLabelColor)
    static let mTextTertiary = Color(.tertiaryLabelColor)
    #endif

    // Functional state colors — the only "visible" colors
    static let mOnTarget = Color.green      // hit target
    static let mApproaching = Color.orange  // 70-100% of target
    static let mUnder = Color.gray          // < 70%, neutral
    static let mOver = Color.red            // exceeded (calories/fat only)

    // Subtle accent for interactive elements
    static let mAccent = Color.accentColor

    /// A lighter/brighter companion to `mAccent`, used as the bright end of gradients.
    #if canImport(UIKit)
    static var mAccentSecondary: Color {
        Color(uiColor: UIColor(Color.mAccent).resolvedLighter(by: 0.18))
    }
    #else
    static var mAccentSecondary: Color {
        Color.mAccent.opacity(0.78)
    }
    #endif

    /// A gentle base→slightly-lighter gradient for hero fills (rings, bars).
    /// Flows top-leading → bottom-trailing.
    static func macroGradient(_ base: Color) -> LinearGradient {
        LinearGradient(
            colors: [base, base.lighter(by: 0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Accent gradient (`mAccent` → `mAccentSecondary`) for primary CTAs.
    static var mAccentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.mAccent, Color.mAccentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Returns the appropriate target color based on progress ratio.
    /// - Parameters:
    ///   - ratio: current / target (e.g. 0.85 means 85% of target)
    ///   - isOverBad: true for calories/fat (red when over), false for protein (green when over)
    static func targetColor(ratio: Double, isOverBad: Bool = false) -> Color {
        if ratio >= 1.0 {
            return isOverBad ? .mOver : .mOnTarget
        } else if ratio >= 0.7 {
            return .mApproaching
        } else {
            return .mUnder
        }
    }

    /// Returns a slightly brighter variant of the color for gradient accents.
    /// Blends toward white by `amount` (0...1) so functional semantics are preserved.
    func lighter(by amount: CGFloat) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor(self).resolvedLighter(by: amount))
        #else
        // Layer a translucent white wash to brighten on platforms without UIColor blending.
        return self.opacity(1.0 - Double(amount) * 0.35)
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    /// Resolves the (possibly dynamic) color in the current trait environment and
    /// blends it toward white by `amount` (0...1) to produce a brighter shade.
    func resolvedLighter(by amount: CGFloat) -> UIColor {
        let resolved = resolvedColor(with: .current)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        let t = max(0, min(1, amount))
        return UIColor(
            red: r + (1 - r) * t,
            green: g + (1 - g) * t,
            blue: b + (1 - b) * t,
            alpha: a
        )
    }
}
#endif

// MARK: - Card surface & section styling

extension View {
    /// Soft, elevated card surface — a continuous-corner squircle filled with
    /// `mBgSecondary` plus a subtle drop shadow. Drop-in replacement for the legacy
    /// `.background(RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius).fill(Color.mBgSecondary))`.
    /// Callers keep their own padding.
    func mCard(cornerRadius: CGFloat = DesignConstants.cardCornerRadius) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.mBgSecondary)
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }

    /// Section-title text styling — confident type, primary color, leading-aligned.
    func mSectionTitle() -> some View {
        self
            .font(.mTitle3)
            .foregroundStyle(Color.mTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
