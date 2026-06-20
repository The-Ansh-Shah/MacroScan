#if canImport(UIKit)
import UIKit

enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
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

    /// Rigid impact on destructive actions (delete, remove)
    static func deleted() {
        rigidImpact.impactOccurred()
    }

    /// Warning notification for critical safety rules
    static func warning() {
        notification.notificationOccurred(.warning)
    }

    /// Selection feedback on segmented control changes
    static func selectionChanged() {
        selection.selectionChanged()
    }
}
#else
enum Haptics {
    static func logFood() {}
    static func targetHit() {}
    static func sheetDismissed() {}
    static func deleted() {}
    static func warning() {}
    static func selectionChanged() {}
}
#endif
