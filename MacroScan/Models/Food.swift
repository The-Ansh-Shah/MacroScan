import Foundation
import SwiftData

@Model
final class Food {
    var name: String
    var brand: String?
    var barcode: String?
    var diningLocationRaw: String?
    var servingSizeGrams: Double

    // Macros per servingSizeGrams
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var ironMg: Double
    var vitaminDMcg: Double
    var vitaminB12Mcg: Double

    // Flags
    var sourceRaw: String
    var isVegetarian: Bool
    var containsEggs: Bool
    var containsMushrooms: Bool
    var isFavorite: Bool

    // Ranking bookkeeping
    var timesLogged: Int
    var lastLoggedAt: Date?
    var createdAt: Date

    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var diningLocation: DiningLocation? {
        get {
            guard let raw = diningLocationRaw else { return nil }
            return DiningLocation(rawValue: raw)
        }
        set { diningLocationRaw = newValue?.rawValue }
    }

    init(
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        diningLocation: DiningLocation? = nil,
        servingSizeGrams: Double,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double = 0,
        ironMg: Double = 0,
        vitaminDMcg: Double = 0,
        vitaminB12Mcg: Double = 0,
        source: FoodSource,
        isVegetarian: Bool = true,
        containsEggs: Bool = false,
        containsMushrooms: Bool = false,
        isFavorite: Bool = false
    ) {
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.diningLocationRaw = diningLocation?.rawValue
        self.servingSizeGrams = servingSizeGrams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.ironMg = ironMg
        self.vitaminDMcg = vitaminDMcg
        self.vitaminB12Mcg = vitaminB12Mcg
        self.sourceRaw = source.rawValue
        self.isVegetarian = isVegetarian
        self.containsEggs = containsEggs
        self.containsMushrooms = containsMushrooms
        self.isFavorite = isFavorite
        self.timesLogged = 0
        self.lastLoggedAt = nil
        self.createdAt = Date()
    }

    /// Scale macros by grams eaten relative to serving size
    func macros(forGrams grams: Double) -> ScaledMacros {
        let ratio = grams / servingSizeGrams
        return ScaledMacros(
            calories: calories * ratio,
            proteinG: proteinG * ratio,
            carbsG: carbsG * ratio,
            fatG: fatG * ratio,
            fiberG: fiberG * ratio,
            ironMg: ironMg * ratio,
            vitaminDMcg: vitaminDMcg * ratio,
            vitaminB12Mcg: vitaminB12Mcg * ratio
        )
    }
}

struct ScaledMacros {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let ironMg: Double
    let vitaminDMcg: Double
    let vitaminB12Mcg: Double

    static let zero = ScaledMacros(
        calories: 0, proteinG: 0, carbsG: 0, fatG: 0,
        fiberG: 0, ironMg: 0, vitaminDMcg: 0, vitaminB12Mcg: 0
    )

    static func + (lhs: ScaledMacros, rhs: ScaledMacros) -> ScaledMacros {
        ScaledMacros(
            calories: lhs.calories + rhs.calories,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG,
            fatG: lhs.fatG + rhs.fatG,
            fiberG: lhs.fiberG + rhs.fiberG,
            ironMg: lhs.ironMg + rhs.ironMg,
            vitaminDMcg: lhs.vitaminDMcg + rhs.vitaminDMcg,
            vitaminB12Mcg: lhs.vitaminB12Mcg + rhs.vitaminB12Mcg
        )
    }
}
