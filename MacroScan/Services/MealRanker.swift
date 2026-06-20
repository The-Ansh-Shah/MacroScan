import Foundation

/// Pure algorithmic food ranking — no AI.
/// Score = timesLogged * exp(-daysSinceLastLogged / 14)
/// Surfaces foods you actually eat, with recency decay.
struct MealRanker {
    /// Rank foods by personal eating pattern score
    static func rank(foods: [Food], limit: Int = 5) -> [Food] {
        let now = Date()
        let scored = foods.compactMap { food -> (Food, Double)? in
            guard food.timesLogged > 0, let lastLogged = food.lastLoggedAt else { return nil }
            let daysSince = Double(lastLogged.daysUntil(now))
            let score = Double(food.timesLogged) * exp(-daysSince / 14.0)
            return (food, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Find foods that best close the gap between current totals and targets.
    /// Returns foods sorted by how well they fill the biggest nutritional gap.
    static func closeGapSuggestions(
        foods: [Food],
        currentTotals: ScaledMacros,
        profile: UserProfile,
        limit: Int = 10
    ) -> [Food] {
        let calorieGap = max(0, profile.calorieTarget - currentTotals.calories)
        let proteinGap = max(0, profile.proteinTargetG - currentTotals.proteinG)
        let fiberGap = max(0, profile.fiberTargetG - currentTotals.fiberG)

        // Skip if already at target
        guard calorieGap > 0 || proteinGap > 0 else { return [] }

        let scored = foods.compactMap { food -> (Food, Double)? in
            // Respect dietary preferences (vegetarian / egg / mushroom exclusions).
            guard food.isAllowed(for: profile) else { return nil }
            // Skip foods that would blow the calorie budget
            guard food.calories <= calorieGap + 50 else { return nil }

            // Score: how much protein/fiber gap it closes, weighted by protein
            // density (g protein per calorie) so lean, high-protein vegetarian
            // options outrank calorie-dense ones on a cut.
            let proteinFill = min(food.proteinG, proteinGap)
            let fiberFill = min(food.fiberG, fiberGap)
            let proteinPerCal = food.proteinG / max(food.calories, 1)
            let score = (proteinFill * 3.0 + fiberFill) * (1.0 + proteinPerCal * 4.0)

            // Boost from recency
            let recencyBoost: Double
            if let lastLogged = food.lastLoggedAt {
                let daysSince = Double(lastLogged.daysUntil(Date()))
                recencyBoost = exp(-daysSince / 14.0)
            } else {
                recencyBoost = 0.1
            }

            return (food, score * (1.0 + recencyBoost))
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
