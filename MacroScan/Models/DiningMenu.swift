import Foundation
import SwiftData

@Model
final class DiningMenu {
    var locationRaw: String
    var date: Date
    var mealPeriod: String
    var items: [DiningMenuItem]
    var lastFetched: Date

    var location: DiningLocation {
        get { DiningLocation(rawValue: locationRaw) ?? .crossroads }
        set { locationRaw = newValue.rawValue }
    }

    init(
        location: DiningLocation,
        date: Date,
        mealPeriod: String,
        items: [DiningMenuItem] = [],
        lastFetched: Date = Date()
    ) {
        self.locationRaw = location.rawValue
        self.date = date
        self.mealPeriod = mealPeriod
        self.items = items
        self.lastFetched = lastFetched
    }
}

struct DiningMenuItem: Codable, Identifiable {
    var id: String { name + category }

    let name: String
    let category: String
    let servingGrams: Double?
    let calories: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let ironMg: Double?
    let vitaminDMcg: Double?
    let vitaminB12Mcg: Double?
    let tags: [String]
    let allergens: [String]

    /// Whether this item has enough nutrition data for the optimizer
    var hasCompleteNutrition: Bool {
        calories != nil && proteinG != nil && carbsG != nil && fatG != nil
    }
}
