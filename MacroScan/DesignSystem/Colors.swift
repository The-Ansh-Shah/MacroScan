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
}
