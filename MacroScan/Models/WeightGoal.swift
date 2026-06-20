import Foundation
import SwiftData

/// A user's active (or past) weight/body-composition goal.
/// `GoalPlannerView` sets one of these; `GoalProgressView` charts progress against the linear projection.
@Model
final class WeightGoal {
    var startedAt: Date
    var targetWeightLb: Double?
    var targetBodyFatPct: Double?
    var targetDate: Date
    var isActive: Bool
    var startingWeightLb: Double
    var startingBodyFatPct: Double?
    var exportID: UUID = UUID()

    init(
        startedAt: Date = Date(),
        targetWeightLb: Double? = nil,
        targetBodyFatPct: Double? = nil,
        targetDate: Date,
        isActive: Bool = true,
        startingWeightLb: Double,
        startingBodyFatPct: Double? = nil
    ) {
        self.startedAt = startedAt
        self.targetWeightLb = targetWeightLb
        self.targetBodyFatPct = targetBodyFatPct
        self.targetDate = targetDate
        self.isActive = isActive
        self.startingWeightLb = startingWeightLb
        self.startingBodyFatPct = startingBodyFatPct
    }
}
