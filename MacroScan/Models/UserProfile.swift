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
    var bodyWeightLb: Double?

    var dietGoal: DietGoal {
        get { DietGoal(rawValue: dietGoalRaw) ?? .cut }
        set { dietGoalRaw = newValue.rawValue }
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
        bodyWeightLb: Double? = nil
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
    }
}
