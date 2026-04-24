import SwiftUI

extension Font {
    static let mLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let mTitle = Font.system(.title, design: .rounded, weight: .semibold)
    static let mTitle2 = Font.system(.title2, design: .rounded, weight: .semibold)
    static let mTitle3 = Font.system(.title3, design: .rounded, weight: .medium)
    static let mHeadline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let mBody = Font.system(.body, design: .rounded)
    static let mCallout = Font.system(.callout, design: .rounded)
    static let mSubheadline = Font.system(.subheadline, design: .rounded)
    static let mCaption = Font.system(.caption, design: .rounded)

    // Monospaced digits for large numbers in macro displays
    static let mStatNumber = Font.system(.title, design: .rounded, weight: .bold)
        .monospacedDigit()
    static let mStatNumberLarge = Font.system(.largeTitle, design: .rounded, weight: .bold)
        .monospacedDigit()
}
