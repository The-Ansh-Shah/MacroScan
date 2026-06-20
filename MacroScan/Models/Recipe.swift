import Foundation
import SwiftData

@Model
final class Recipe {
    var name: String
    var notes: String?
    /// Step-by-step preparation instructions (newline-separated). Default "" for migration.
    var instructions: String = ""
    var totalServings: Double
    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]
    var createdAt: Date
    var lastUsedAt: Date?
    var timesUsed: Int
    var isFavorite: Bool
    var exportID: UUID = UUID()

    var perServingMacros: ScaledMacros {
        guard totalServings > 0 else { return .zero }
        let total = ingredients.reduce(ScaledMacros.zero) { sum, ing in
            guard let food = ing.food else { return sum }
            return sum + food.macros(forGrams: ing.grams)
        }
        let scale = 1.0 / totalServings
        return ScaledMacros(
            calories: total.calories * scale,
            proteinG: total.proteinG * scale,
            carbsG: total.carbsG * scale,
            fatG: total.fatG * scale,
            fiberG: total.fiberG * scale,
            ironMg: total.ironMg * scale,
            vitaminDMcg: total.vitaminDMcg * scale,
            vitaminB12Mcg: total.vitaminB12Mcg * scale
        )
    }

    init(
        name: String,
        notes: String? = nil,
        instructions: String = "",
        totalServings: Double = 1,
        ingredients: [RecipeIngredient] = [],
        isFavorite: Bool = false
    ) {
        self.name = name
        self.notes = notes
        self.instructions = instructions
        self.totalServings = totalServings
        self.ingredients = ingredients
        self.createdAt = Date()
        self.lastUsedAt = nil
        self.timesUsed = 0
        self.isFavorite = isFavorite
    }
}

@Model
final class RecipeIngredient {
    var recipe: Recipe?
    var food: Food?
    var grams: Double
    var order: Int

    init(food: Food? = nil, grams: Double, order: Int = 0) {
        self.food = food
        self.grams = grams
        self.order = order
    }
}
