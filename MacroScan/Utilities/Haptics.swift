import UIKit

enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// Light impact on every tap that logs a food
    static func logFood() {
        lightImpact.impactOccurred()
    }

    /// Success notification when daily macro target is first hit
    static func targetHit() {
        notification.notificationOccurred(.success)
    }

    /// Soft impact on sheet dismissal
    static func sheetDismissed() {
        softImpact.impactOccurred()
    }

    /// Selection feedback on segmented control changes
    static func selectionChanged() {
        selection.selectionChanged()
    }
}
