import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum DesignConstants {
    static let cardCornerRadius: CGFloat = 16
    static let ringStrokeWidth: CGFloat = 12
    static let barHeight: CGFloat = 8
    static let minTapTarget: CGFloat = 56
    static let ringAnimation = Animation.easeOut(duration: 1.2)
    static let springAnimation = Animation.spring(response: 0.4, dampingFraction: 0.8)
}
