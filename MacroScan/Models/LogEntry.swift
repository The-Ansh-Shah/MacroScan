import Foundation
import SwiftData

@Model
final class LogEntry {
    var food: Food?
    var gramsEaten: Double
    var servingsEaten: Double?
    var mealTypeRaw: String
    var loggedAt: Date
    var photoData: Data?
    var aiConfidence: Double?
    var notes: String?

    var exportID: UUID = UUID()

    // Quick-add fields (food == nil)
    var quickAddCalories: Double?
    var quickAddProteinG: Double?
    var quickAddCarbsG: Double?
    var quickAddFatG: Double?
    var quickAddFiberG: Double?
    var quickAddName: String?

    var isQuickAdd: Bool { food == nil && quickAddCalories != nil }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var scaledMacros: ScaledMacros {
        if let food {
            return food.macros(forGrams: gramsEaten)
        }
        return ScaledMacros(
            calories: quickAddCalories ?? 0,
            proteinG: quickAddProteinG ?? 0,
            carbsG: quickAddCarbsG ?? 0,
            fatG: quickAddFatG ?? 0,
            fiberG: quickAddFiberG ?? 0,
            ironMg: 0,
            vitaminDMcg: 0,
            vitaminB12Mcg: 0
        )
    }

    var displayName: String {
        if let food { return food.name }
        return quickAddName ?? "Quick add"
    }

    init(
        food: Food?,
        gramsEaten: Double,
        mealType: MealType,
        loggedAt: Date = Date(),
        photoData: Data? = nil,
        aiConfidence: Double? = nil,
        notes: String? = nil
    ) {
        self.food = food
        self.gramsEaten = gramsEaten
        self.mealTypeRaw = mealType.rawValue
        self.loggedAt = loggedAt
        self.photoData = photoData
        self.aiConfidence = aiConfidence
        self.notes = notes
    }
}
