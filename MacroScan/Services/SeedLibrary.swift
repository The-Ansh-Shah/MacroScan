import Foundation
import SwiftData

/// First-launch curated vegetarian (egg- and mushroom-free) high-protein library.
/// Inserted once by `RootView`; every item uses `FoodSource.curated` so it can be
/// browsed, filtered, or reset independently of user-created foods.
///
/// Macros are per the listed serving size (grams). Values are realistic approximations
/// for a high-protein cut; the user can edit any item after logging it.
enum SeedLibrary {

    /// Idempotent: inserts the library only if no curated foods already exist.
    static func seedIfNeeded(into context: ModelContext) {
        let existing = FetchDescriptor<Food>(
            predicate: #Predicate { $0.sourceRaw == "curated" }
        )
        let count = (try? context.fetchCount(existing)) ?? 0
        guard count == 0 else { return }
        seed(into: context)
    }

    private static func seed(into context: ModelContext) {
        for spec in foodSpecs {
            context.insert(spec.makeFood())
        }
    }

    // MARK: - Remove earlier "filler" recipes

    /// Names of placeholder recipes seeded by earlier app versions. AI generation is now
    /// the recipe path, so these are removed once — but only if the user never used them.
    private static let legacySeedRecipeNames: Set<String> = [
        "High-Protein Tofu Bowl",
        "Chickpea Pasta & Lentils",
        "Greek Yogurt Protein Bowl",
        "Tempeh & Black Bean Bowl",
        "Cottage Cheese Snack Plate",
    ]

    /// One-time cleanup of the old seeded filler recipes from existing installs.
    static func removeLegacySeededRecipesIfNeeded(into context: ModelContext) {
        let key = "didRemoveSeedRecipesV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        for recipe in recipes where legacySeedRecipeNames.contains(recipe.name) && recipe.timesUsed == 0 {
            context.delete(recipe)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Food specs

    /// name, serving grams, cal, protein, carbs, fat, fiber, iron(mg), B12(mcg), vitD(mcg)
    private struct FoodSpec {
        let name: String
        let serving: Double
        let cal: Double
        let p: Double
        let c: Double
        let f: Double
        let fiber: Double
        var iron: Double = 0
        var b12: Double = 0
        var vitD: Double = 0

        func makeFood() -> Food {
            Food(
                name: name,
                servingSizeGrams: serving,
                calories: cal,
                proteinG: p,
                carbsG: c,
                fatG: f,
                fiberG: fiber,
                ironMg: iron,
                vitaminDMcg: vitD,
                vitaminB12Mcg: b12,
                source: .curated,
                isVegetarian: true,
                containsEggs: false,
                containsMushrooms: false
            )
        }
    }

    private static let foodSpecs: [FoodSpec] = [
        FoodSpec(name: "Extra-firm tofu", serving: 100, cal: 120, p: 19, c: 2, f: 5, fiber: 1, iron: 2.5),
        FoodSpec(name: "Tempeh", serving: 100, cal: 192, p: 20, c: 8, f: 11, fiber: 6, iron: 2.7),
        FoodSpec(name: "Seitan", serving: 100, cal: 150, p: 25, c: 6, f: 2, fiber: 1, iron: 1.5),
        FoodSpec(name: "Textured vegetable protein (dry)", serving: 30, cal: 102, p: 16, c: 9, f: 0.4, fiber: 5, iron: 2.4),
        FoodSpec(name: "Edamame (shelled)", serving: 100, cal: 121, p: 12, c: 9, f: 5, fiber: 5, iron: 2.3),
        FoodSpec(name: "Nonfat Greek yogurt", serving: 170, cal: 100, p: 17, c: 6, f: 0, fiber: 0, b12: 1.3),
        FoodSpec(name: "Skyr (nonfat)", serving: 170, cal: 110, p: 19, c: 7, f: 0, fiber: 0, b12: 1.2),
        FoodSpec(name: "Low-fat cottage cheese", serving: 100, cal: 72, p: 12, c: 3, f: 1, fiber: 0, b12: 0.4),
        FoodSpec(name: "Paneer", serving: 100, cal: 265, p: 18, c: 4, f: 20, fiber: 0, b12: 0.9),
        FoodSpec(name: "Fortified soy milk (unsweetened)", serving: 240, cal: 80, p: 7, c: 4, f: 4, fiber: 1, b12: 1.2, vitD: 2.5),
        FoodSpec(name: "Cooked lentils", serving: 100, cal: 116, p: 9, c: 20, f: 0.4, fiber: 8, iron: 3.3),
        FoodSpec(name: "Cooked chickpeas", serving: 100, cal: 164, p: 9, c: 27, f: 3, fiber: 8, iron: 2.9),
        FoodSpec(name: "Cooked black beans", serving: 100, cal: 132, p: 9, c: 24, f: 0.5, fiber: 9, iron: 2.1),
        FoodSpec(name: "Chickpea pasta (dry)", serving: 57, cal: 190, p: 14, c: 32, f: 3, fiber: 8, iron: 4.0),
        FoodSpec(name: "Nutritional yeast", serving: 16, cal: 60, p: 8, c: 5, f: 1, fiber: 3, iron: 1.0, b12: 7.8),
        FoodSpec(name: "Pumpkin seeds", serving: 30, cal: 151, p: 9, c: 5, f: 13, fiber: 2, iron: 2.5),
        FoodSpec(name: "Roasted chickpeas (snack)", serving: 30, cal: 120, p: 6, c: 18, f: 2, fiber: 5, iron: 1.5),
        FoodSpec(name: "Protein powder (1 scoop)", serving: 32, cal: 120, p: 25, c: 3, f: 1.5, fiber: 1, b12: 1.0),
    ]
}
