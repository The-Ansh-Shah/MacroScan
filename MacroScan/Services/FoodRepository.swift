import Foundation
import SwiftData

/// Central CRUD + aggregation over SwiftData food/log models
@MainActor
class FoodRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Food

    func save(food: Food) {
        modelContext.insert(food)
    }

    func findByBarcode(_ barcode: String) -> Food? {
        let descriptor = FetchDescriptor<Food>(
            predicate: #Predicate { $0.barcode == barcode }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func topFoods(limit: Int = 10) -> [Food] {
        var descriptor = FetchDescriptor<Food>(
            sortBy: [SortDescriptor(\Food.timesLogged, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allFoods() -> [Food] {
        let descriptor = FetchDescriptor<Food>(
            sortBy: [SortDescriptor(\Food.lastLoggedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Log Entries

    func logFood(_ food: Food, grams: Double, mealType: MealType, photoData: Data? = nil, aiConfidence: Double? = nil) {
        let entry = LogEntry(
            food: food,
            gramsEaten: grams,
            mealType: mealType,
            photoData: photoData,
            aiConfidence: aiConfidence
        )
        modelContext.insert(entry)

        // Update ranking bookkeeping
        food.timesLogged += 1
        food.lastLoggedAt = Date()
    }

    func deleteEntry(_ entry: LogEntry) {
        modelContext.delete(entry)
    }

    func entriesForDate(_ date: Date) -> [LogEntry] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { entry in
                entry.loggedAt >= startOfDay && entry.loggedAt < endOfDay
            },
            sortBy: [SortDescriptor(\LogEntry.loggedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func dailyTotals(forDate date: Date) -> ScaledMacros {
        entriesForDate(date).reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
    }

    func entriesForWeek(startingFrom date: Date) -> [LogEntry] {
        let start = date.startOfWeek
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { entry in
                entry.loggedAt >= start && entry.loggedAt < end
            },
            sortBy: [SortDescriptor(\LogEntry.loggedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - User Profile

    func userProfile() -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>()
        return try? modelContext.fetch(descriptor).first
    }
}
