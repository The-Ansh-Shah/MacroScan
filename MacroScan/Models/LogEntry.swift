import Foundation
import SwiftData

@Model
final class LogEntry {
    var food: Food?
    var gramsEaten: Double
    var mealTypeRaw: String
    var loggedAt: Date
    var photoData: Data?
    var aiConfidence: Double?

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    /// Scaled macros based on grams eaten
    var scaledMacros: ScaledMacros {
        guard let food else { return .zero }
        return food.macros(forGrams: gramsEaten)
    }

    init(
        food: Food?,
        gramsEaten: Double,
        mealType: MealType,
        loggedAt: Date = Date(),
        photoData: Data? = nil,
        aiConfidence: Double? = nil
    ) {
        self.food = food
        self.gramsEaten = gramsEaten
        self.mealTypeRaw = mealType.rawValue
        self.loggedAt = loggedAt
        self.photoData = photoData
        self.aiConfidence = aiConfidence
    }
}
