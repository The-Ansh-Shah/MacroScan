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

    func logFood(
        _ food: Food,
        grams: Double,
        mealType: MealType,
        servings: Double? = nil,
        photoData: Data? = nil,
        aiConfidence: Double? = nil,
        notes: String? = nil
    ) {
        let entry = LogEntry(
            food: food,
            gramsEaten: grams,
            mealType: mealType,
            photoData: photoData,
            aiConfidence: aiConfidence,
            notes: notes
        )
        entry.servingsEaten = servings
        modelContext.insert(entry)

        food.timesLogged += 1
        food.lastLoggedAt = Date()

        Task {
            try? await HealthKitService.shared.writeNutrition(entry)
        }
    }

    func deleteEntry(_ entry: LogEntry) {
        modelContext.delete(entry)
    }

    /// Update an existing log entry in place (grams, meal type, notes, loggedAt).
    func updateEntry(
        _ entry: LogEntry,
        grams: Double,
        mealType: MealType,
        loggedAt: Date? = nil,
        notes: String? = nil,
        servings: Double? = nil
    ) {
        entry.gramsEaten = grams
        entry.servingsEaten = servings
        entry.mealType = mealType
        if let loggedAt { entry.loggedAt = loggedAt }
        entry.notes = notes
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

    /// Best default meal type: reuse the meal you logged into within the last ~90 min,
    /// otherwise fall back to the time-of-day guess. Cuts the most frequent picker correction.
    func suggestedMealType(now: Date = Date()) -> MealType {
        let recent = entriesForDate(now)
            .filter { $0.loggedAt <= now && now.timeIntervalSince($0.loggedAt) <= 90 * 60 }
            .max { $0.loggedAt < $1.loggedAt }
        return recent?.mealType ?? .currentGuess
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

    /// Daily logged calories for the trailing `days`, excluding days with no intake.
    /// Used to estimate empirical/adaptive TDEE from real eating data.
    func trailingDailyIntake(days: Int) -> [(date: Date, kcal: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [(date: Date, kcal: Double)] = []
        for daysAgo in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let kcal = dailyTotals(forDate: date).calories
            if kcal > 0 { out.append((date: date, kcal: kcal)) }
        }
        return out
    }

    // MARK: - User Profile

    func userProfile() -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>()
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Quick Add

    func logQuickAdd(
        name: String?,
        calories: Double,
        proteinG: Double?,
        carbsG: Double?,
        fatG: Double?,
        fiberG: Double?,
        mealType: MealType,
        notes: String?
    ) {
        let entry = LogEntry(food: nil, gramsEaten: 0, mealType: mealType, notes: notes)
        entry.quickAddCalories = calories
        entry.quickAddProteinG = proteinG
        entry.quickAddCarbsG = carbsG
        entry.quickAddFatG = fatG
        entry.quickAddFiberG = fiberG
        entry.quickAddName = name
        modelContext.insert(entry)

        Task {
            try? await HealthKitService.shared.writeNutrition(entry)
        }
    }

    func updateQuickAddEntry(
        _ entry: LogEntry,
        name: String?,
        calories: Double,
        proteinG: Double?,
        carbsG: Double?,
        fatG: Double?,
        fiberG: Double?,
        mealType: MealType,
        notes: String?
    ) {
        entry.quickAddName = name
        entry.quickAddCalories = calories
        entry.quickAddProteinG = proteinG
        entry.quickAddCarbsG = carbsG
        entry.quickAddFatG = fatG
        entry.quickAddFiberG = fiberG
        entry.mealType = mealType
        entry.notes = notes
    }

    // MARK: - Copy Meals

    @discardableResult
    func copyMeal(from sourceDate: Date, to destDate: Date, mealType: MealType) -> Int {
        let entries = entriesForDate(sourceDate).filter { $0.mealType == mealType }
        for entry in entries {
            let ts = destTimestamp(sourceEntry: entry, sourceDate: sourceDate, destDate: destDate)
            copyEntry(entry, to: ts, mealType: mealType)
        }
        return entries.count
    }

    @discardableResult
    func copyAllMeals(from sourceDate: Date, to destDate: Date) -> Int {
        let entries = entriesForDate(sourceDate)
        for entry in entries {
            let ts = destTimestamp(sourceEntry: entry, sourceDate: sourceDate, destDate: destDate)
            copyEntry(entry, to: ts, mealType: entry.mealType)
        }
        return entries.count
    }

    private func copyEntry(_ entry: LogEntry, to timestamp: Date, mealType: MealType) {
        if entry.isQuickAdd {
            let new = LogEntry(food: nil, gramsEaten: 0, mealType: mealType, loggedAt: timestamp, notes: entry.notes)
            new.quickAddCalories = entry.quickAddCalories
            new.quickAddProteinG = entry.quickAddProteinG
            new.quickAddCarbsG = entry.quickAddCarbsG
            new.quickAddFatG = entry.quickAddFatG
            new.quickAddFiberG = entry.quickAddFiberG
            new.quickAddName = entry.quickAddName
            modelContext.insert(new)
        } else if let food = entry.food {
            let new = LogEntry(
                food: food,
                gramsEaten: entry.gramsEaten,
                mealType: mealType,
                loggedAt: timestamp,
                notes: entry.notes
            )
            modelContext.insert(new)
            food.timesLogged += 1
            food.lastLoggedAt = timestamp
        }
    }

    private func destTimestamp(sourceEntry: LogEntry, sourceDate: Date, destDate: Date) -> Date {
        let cal = Calendar.current
        let sourceStart = cal.startOfDay(for: sourceDate)
        let offset = sourceEntry.loggedAt.timeIntervalSince(sourceStart)
        let destStart = cal.startOfDay(for: destDate)
        return destStart.addingTimeInterval(offset)
    }

    // MARK: - Body Measurements

    /// Latest recorded `BodyMeasurement`, or nil if none exist.
    /// Prefer this over `UserProfile.bodyWeightLb` — the profile field is a manual-override fallback only.
    func latestBodyMeasurement() -> BodyMeasurement? {
        var descriptor = FetchDescriptor<BodyMeasurement>(
            sortBy: [SortDescriptor(\BodyMeasurement.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Single source of truth for "current weight". Prefers the latest BodyMeasurement,
    /// falls back to the manual-override `UserProfile.bodyWeightLb`.
    func currentWeightLb(profile: UserProfile) -> Double? {
        if let m = latestBodyMeasurement() { return m.weightLb }
        return profile.bodyWeightLb
    }

    // MARK: - Recipes

    func saveRecipe(_ recipe: Recipe) {
        modelContext.insert(recipe)
    }

    func deleteRecipe(_ recipe: Recipe) {
        modelContext.delete(recipe)
    }

    func recipes(favoritesFirst: Bool = true) -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>(
            sortBy: [SortDescriptor(\Recipe.lastUsedAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        guard favoritesFirst else { return all }
        return all.sorted { ($0.isFavorite ? 0 : 1) < ($1.isFavorite ? 0 : 1) }
    }

    @discardableResult
    func logRecipe(
        _ recipe: Recipe,
        servings: Double,
        mealType: MealType,
        loggedAt: Date = Date(),
        notes: String? = nil
    ) -> [LogEntry] {
        let scale = servings / recipe.totalServings
        var entries: [LogEntry] = []

        for ingredient in recipe.ingredients.sorted(by: { $0.order < $1.order }) {
            guard let food = ingredient.food else { continue }
            let grams = ingredient.grams * scale
            let entryNotes: String
            if let userNotes = notes, !userNotes.isEmpty {
                entryNotes = "\(userNotes)\nfrom recipe: \(recipe.name)"
            } else {
                entryNotes = "from recipe: \(recipe.name)"
            }
            let entry = LogEntry(
                food: food,
                gramsEaten: grams,
                mealType: mealType,
                loggedAt: loggedAt,
                notes: entryNotes
            )
            modelContext.insert(entry)
            food.timesLogged += 1
            food.lastLoggedAt = loggedAt
            entries.append(entry)
        }

        recipe.timesUsed += 1
        recipe.lastUsedAt = loggedAt
        return entries
    }

    // MARK: - Adherence

    struct AdherenceStats {
        var loggedDays: Int
        var totalDays: Int
        var hitCalorieTargetDays: Int
        var hitProteinTargetDays: Int
    }

    func adherence(forLastDays days: Int) -> AdherenceStats {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let profile = userProfile()
        var loggedDays = 0
        var hitCalorie = 0
        var hitProtein = 0

        for daysAgo in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let totals = dailyTotals(forDate: date)
            guard totals.calories > 0 else { continue }
            loggedDays += 1

            if let target = profile?.calorieTarget, target > 0 {
                let ratio = totals.calories / target
                if ratio >= 0.9 && ratio <= 1.1 { hitCalorie += 1 }
            }
            if let target = profile?.proteinTargetG, target > 0, totals.proteinG >= target {
                hitProtein += 1
            }
        }

        return AdherenceStats(
            loggedDays: loggedDays,
            totalDays: days,
            hitCalorieTargetDays: hitCalorie,
            hitProteinTargetDays: hitProtein
        )
    }

    // MARK: - Balance Flags

    /// Compute daily-balance flags for a given date + profile.
    /// Only returns flags relevant for the current day; past-day review is flag-free.
    func balanceFlags(forDate date: Date, profile: UserProfile) -> [BalanceFlag] {
        let isToday = Calendar.current.isDateInToday(date)
        guard isToday else { return [] }

        let totals = dailyTotals(forDate: date)
        let hour = Calendar.current.component(.hour, from: Date())
        let dayKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: date))

        var flags: [BalanceFlag] = []

        // Protein low after 6pm
        if hour >= 18, profile.proteinTargetG > 0 {
            let ratio = totals.proteinG / profile.proteinTargetG
            if ratio < 0.7 {
                flags.append(BalanceFlag(
                    id: "proteinLow-\(dayKey)",
                    kind: .proteinLow,
                    severity: ratio < 0.5 ? .warning : .info,
                    title: "Protein running low",
                    message: "You're at \(Int(ratio * 100))% of today's protein target with evening coming up.",
                    deepLink: .closeGap
                ))
            }
        }

        // Fiber low after 6pm
        if hour >= 18, profile.fiberTargetG > 0 {
            let ratio = totals.fiberG / profile.fiberTargetG
            if ratio < 0.5 {
                flags.append(BalanceFlag(
                    id: "fiberLow-\(dayKey)",
                    kind: .fiberLow,
                    severity: .info,
                    title: "Fiber low today",
                    message: "You're at \(Int(ratio * 100))% of fiber target. Consider vegetables or legumes.",
                    deepLink: .closeGap
                ))
            }
        }

        // Fat excessive
        if profile.fatTargetG > 0 {
            let ratio = totals.fatG / profile.fatTargetG
            if ratio > 1.5 {
                flags.append(BalanceFlag(
                    id: "fatExcessive-\(dayKey)",
                    kind: .fatExcessive,
                    severity: .warning,
                    title: "Fat well over target",
                    message: "Today's fat is \(Int(ratio * 100))% of target. Nothing wrong with one day, worth noticing if it's a pattern.",
                    deepLink: nil
                ))
            }
        }

        // Calorie deficit too large — use TDEE when profile has enough data.
        // Pass the latest measured weight so TDEE reflects reality, not a stale profile field.
        let currentWeight = currentWeightLb(profile: profile)
        if let tdee = BodyCompositionService.tdee(from: profile, currentWeightLb: currentWeight), tdee > 0 {
            let ratio = totals.calories / tdee
            if ratio < 0.6, totals.calories > 0 {
                flags.append(BalanceFlag(
                    id: "calorieDeficitLarge-\(dayKey)",
                    kind: .calorieDeficitLarge,
                    severity: .critical,
                    title: "Eating under 60% of TDEE",
                    message: "Large deficits are hard to sustain and can backfire. Consider a balanced meal.",
                    deepLink: .closeGap
                ))
            }
        } else if profile.calorieTarget > 0 {
            // Fallback: flag if user is far under their explicit calorie target at day-end.
            if hour >= 20 {
                let ratio = totals.calories / profile.calorieTarget
                if ratio < 0.5, totals.calories > 0 {
                    flags.append(BalanceFlag(
                        id: "calorieDeficitLarge-\(dayKey)",
                        kind: .calorieDeficitLarge,
                        severity: .warning,
                        title: "Well under calorie target",
                        message: "You're at \(Int(ratio * 100))% of today's calorie target with the day nearly over.",
                        deepLink: .closeGap
                    ))
                }
            }
        }

        // Micro streak — check last 5 days for B12/iron/D under target
        let streak = microDeficitStreak(profile: profile, endingOn: date)
        if let streak {
            flags.append(BalanceFlag(
                id: "microDeficit-\(streak.nutrient)-\(dayKey)",
                kind: .microDeficitStreak,
                severity: .warning,
                title: "\(streak.nutrient) under target 5+ days",
                message: "\(streak.days) days running under the \(streak.nutrient) target. Consider foods rich in it.",
                deepLink: .search(query: streak.searchHint)
            ))
        }

        return flags
    }

    private struct MicroStreak {
        let nutrient: String
        let days: Int
        let searchHint: String
    }

    private func microDeficitStreak(profile: UserProfile, endingOn date: Date) -> MicroStreak? {
        let cal = Calendar.current
        let micros: [(name: String, target: Double, search: String, extract: (ScaledMacros) -> Double)] = [
            ("B12", profile.vitaminB12TargetMcg, "vitamin b12", { $0.vitaminB12Mcg }),
            ("Iron", profile.ironTargetMg, "iron", { $0.ironMg }),
            ("Vitamin D", profile.vitaminDTargetMcg, "vitamin d", { $0.vitaminDMcg })
        ]

        for micro in micros where micro.target > 0 {
            var streakDays = 0
            for daysAgo in 0..<14 {
                guard let checkDate = cal.date(byAdding: .day, value: -daysAgo, to: date) else { break }
                let totals = dailyTotals(forDate: checkDate)
                let value = micro.extract(totals)
                if value < micro.target * 0.5 {
                    streakDays += 1
                } else {
                    break
                }
            }
            if streakDays >= 5 {
                return MicroStreak(nutrient: micro.name, days: streakDays, searchHint: micro.search)
            }
        }
        return nil
    }

    // MARK: - Water

    @discardableResult
    func logWater(ml: Double, at date: Date = Date()) -> WaterEntry {
        let entry = WaterEntry(amountMl: ml, recordedAt: date)
        modelContext.insert(entry)
        Task {
            try? await HealthKitService.shared.writeWater(ml: ml, recordedAt: date)
        }
        return entry
    }

    func waterEntries(forDate date: Date) -> [WaterEntry] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return (try? modelContext.fetch(FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.recordedAt >= start && $0.recordedAt < end },
            sortBy: [SortDescriptor(\.recordedAt)]
        ))) ?? []
    }

    func totalWater(forDate date: Date) -> Double {
        waterEntries(forDate: date).reduce(0) { $0 + $1.amountMl }
    }

    func deleteWater(_ entry: WaterEntry) {
        modelContext.delete(entry)
    }
}
