import Foundation
import SwiftData

@Model
final class UserProfile {
    // Macro targets
    var calorieTarget: Double
    var proteinTargetG: Double
    var carbTargetG: Double
    var fatTargetG: Double

    // Micro targets
    var fiberTargetG: Double
    var ironTargetMg: Double
    var vitaminDTargetMcg: Double
    var vitaminB12TargetMcg: Double

    // Preferences
    var dietGoalRaw: String
    var isVegetarian: Bool
    var excludedIngredients: [String]
    /// Manual-override weight. Prefer `FoodRepository.currentWeightLb(profile:)`,
    /// which checks the latest `BodyMeasurement` first and falls back to this field
    /// only when no measurements exist.
    var bodyWeightLb: Double?

    // Body composition profile
    var heightIn: Double?
    var ageYears: Int?
    var biologicalSexRaw: String?
    // Inline defaults are required for SwiftData lightweight migration when
    // adding new non-optional properties to an existing @Model.
    var activityLevelRaw: String = ActivityLevel.sedentary.rawValue
    var dailyStepTarget: Int = 8000
    var dailyWaterTargetMl: Double = 3785

    // Active weight goal (optional relationship)
    var currentGoal: WeightGoal?

    // AI usage counter — local telemetry for user debugging
    var aiCallsTotal: Int = 0
    var aiQuotaErrorsTotal: Int = 0
    var aiLastErrorAt: Date?

    // FatSecret daily request counter (resets each calendar day on next call).
    var fatSecretCallsToday: Int = 0
    var fatSecretCallsResetAt: Date?

    var dietGoal: DietGoal {
        get { DietGoal(rawValue: dietGoalRaw) ?? .cut }
        set { dietGoalRaw = newValue.rawValue }
    }

    var biologicalSex: BiologicalSex {
        get {
            guard let raw = biologicalSexRaw else { return .unspecified }
            return BiologicalSex(rawValue: raw) ?? .unspecified
        }
        set { biologicalSexRaw = newValue.rawValue }
    }

    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevelRaw) ?? .sedentary }
        set { activityLevelRaw = newValue.rawValue }
    }

    init(
        calorieTarget: Double = 1800,
        proteinTargetG: Double = 160,
        carbTargetG: Double = 180,
        fatTargetG: Double = 55,
        fiberTargetG: Double = 30,
        ironTargetMg: Double = 18,
        vitaminDTargetMcg: Double = 15,
        vitaminB12TargetMcg: Double = 2.4,
        dietGoal: DietGoal = .cut,
        isVegetarian: Bool = true,
        excludedIngredients: [String] = ["eggs", "mushrooms"],
        bodyWeightLb: Double? = nil,
        heightIn: Double? = nil,
        ageYears: Int? = nil,
        biologicalSex: BiologicalSex = .unspecified,
        activityLevel: ActivityLevel = .sedentary
    ) {
        self.calorieTarget = calorieTarget
        self.proteinTargetG = proteinTargetG
        self.carbTargetG = carbTargetG
        self.fatTargetG = fatTargetG
        self.fiberTargetG = fiberTargetG
        self.ironTargetMg = ironTargetMg
        self.vitaminDTargetMcg = vitaminDTargetMcg
        self.vitaminB12TargetMcg = vitaminB12TargetMcg
        self.dietGoalRaw = dietGoal.rawValue
        self.isVegetarian = isVegetarian
        self.excludedIngredients = excludedIngredients
        self.bodyWeightLb = bodyWeightLb
        self.heightIn = heightIn
        self.ageYears = ageYears
        self.biologicalSexRaw = biologicalSex.rawValue
        self.activityLevelRaw = activityLevel.rawValue
        self.currentGoal = nil
        self.aiCallsTotal = 0
        self.aiQuotaErrorsTotal = 0
        self.aiLastErrorAt = nil
    }
}
