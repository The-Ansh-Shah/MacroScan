import SwiftUI

/// A daily-balance insight surfaced on DayView's InsightsCard.
/// Generated per-day by `FoodRepository.balanceFlags(forDate:profile:)`.
struct BalanceFlag: Identifiable {
    let id: String          // stable per (kind, date) so session dismissal works
    let kind: Kind
    let severity: Severity
    let title: String
    let message: String
    let deepLink: DeepLink?

    enum Kind: String {
        case proteinLow
        case fiberLow
        case fatExcessive
        case calorieDeficitLarge
    }

    enum Severity {
        case info, warning, critical

        var rank: Int {
            switch self {
            case .info: return 0
            case .warning: return 1
            case .critical: return 2
            }
        }
    }

    enum DeepLink {
        case closeGap
        case search(query: String)
    }

    var symbol: String {
        switch kind {
        case .proteinLow: return "fish"
        case .fiberLow: return "leaf"
        case .fatExcessive: return "drop.fill"
        case .calorieDeficitLarge: return "arrow.down.circle"
        }
    }

    var tint: Color {
        switch severity {
        case .info: return .mAccent
        case .warning: return .mApproaching
        case .critical: return .mOver
        }
    }
}
