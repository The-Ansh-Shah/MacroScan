import Foundation

/// Deterministic dining hall meal optimizer — no AI.
/// Greedy algorithm: iteratively picks highest protein/calorie ratio items
/// that fit remaining budget, respecting dietary restrictions.
struct DiningOptimizer {

    struct OptimizedPlan {
        let items: [PlannedItem]
        let totalCalories: Double
        let totalProteinG: Double
        let totalCarbsG: Double
        let totalFatG: Double
        let totalFiberG: Double
    }

    struct PlannedItem: Identifiable {
        let id = UUID()
        let menuItem: DiningMenuItem
        let location: DiningLocation
        let mealPeriod: String
        let servings: Double
    }

    /// Build an optimized meal plan from available dining hall menus.
    ///
    /// Algorithm (greedy v1):
    /// 1. Filter out non-vegetarian, excluded ingredients, incomplete nutrition
    /// 2. Subtract already-logged totals from targets → remaining budget
    /// 3. Iteratively pick highest protein/calorie ratio item that fits
    /// 4. Repeat until protein target hit or calorie budget exhausted
    static func optimize(
        menus: [DiningMenu],
        currentTotals: ScaledMacros,
        profile: UserProfile
    ) -> OptimizedPlan {
        let remainingCalories = max(0, profile.calorieTarget - currentTotals.calories)
        let remainingProtein = max(0, profile.proteinTargetG - currentTotals.proteinG)

        guard remainingCalories > 50, remainingProtein > 5 else {
            return OptimizedPlan(items: [], totalCalories: 0, totalProteinG: 0, totalCarbsG: 0, totalFatG: 0, totalFiberG: 0)
        }

        // Flatten all available items across menus, filtering by dietary restrictions
        var candidates: [(DiningMenuItem, DiningLocation, String)] = []
        for menu in menus {
            for item in menu.items {
                guard item.hasCompleteNutrition else { continue }
                guard passesExclusions(item: item, profile: profile) else { continue }
                candidates.append((item, menu.location, menu.mealPeriod))
            }
        }

        // Sort by protein/calorie efficiency
        candidates.sort { a, b in
            let ratioA = (a.0.proteinG ?? 0) / max(1, a.0.calories ?? 1)
            let ratioB = (b.0.proteinG ?? 0) / max(1, b.0.calories ?? 1)
            return ratioA > ratioB
        }

        // Greedy selection
        var plan: [PlannedItem] = []
        var caloriesLeft = remainingCalories
        var proteinLeft = remainingProtein

        for (item, location, mealPeriod) in candidates {
            guard caloriesLeft > 50, proteinLeft > 0 else { break }

            let itemCal = item.calories ?? 0
            let itemProtein = item.proteinG ?? 0

            guard itemCal > 0, itemCal <= caloriesLeft + 50 else { continue }

            // How many servings fit?
            let maxByCalories = caloriesLeft / itemCal
            let servings = min(maxByCalories, 2.0) // Cap at 2 servings per item
            let roundedServings = (servings * 2).rounded() / 2 // Round to 0.5

            guard roundedServings >= 0.5 else { continue }

            plan.append(PlannedItem(
                menuItem: item,
                location: location,
                mealPeriod: mealPeriod,
                servings: roundedServings
            ))

            caloriesLeft -= itemCal * roundedServings
            proteinLeft -= itemProtein * roundedServings
        }

        let totalCal = plan.reduce(0.0) { $0 + ($1.menuItem.calories ?? 0) * $1.servings }
        let totalPro = plan.reduce(0.0) { $0 + ($1.menuItem.proteinG ?? 0) * $1.servings }
        let totalCarb = plan.reduce(0.0) { $0 + ($1.menuItem.carbsG ?? 0) * $1.servings }
        let totalFat = plan.reduce(0.0) { $0 + ($1.menuItem.fatG ?? 0) * $1.servings }
        let totalFiber = plan.reduce(0.0) { $0 + ($1.menuItem.fiberG ?? 0) * $1.servings }

        return OptimizedPlan(
            items: plan,
            totalCalories: totalCal,
            totalProteinG: totalPro,
            totalCarbsG: totalCarb,
            totalFatG: totalFat,
            totalFiberG: totalFiber
        )
    }

    /// Check if a menu item passes the user's exclusion filters
    private static func passesExclusions(item: DiningMenuItem, profile: UserProfile) -> Bool {
        let nameLower = item.name.lowercased()
        let tagsLower = item.tags.map { $0.lowercased() }
        let allergensLower = item.allergens.map { $0.lowercased() }

        // Vegetarian check
        if profile.isVegetarian {
            let meatKeywords = ["chicken", "beef", "pork", "fish", "salmon", "turkey", "lamb", "shrimp"]
            if meatKeywords.contains(where: { nameLower.contains($0) }) { return false }
        }

        // Excluded ingredients
        for exclusion in profile.excludedIngredients {
            let lower = exclusion.lowercased()
            if nameLower.contains(lower) { return false }
            if tagsLower.contains(lower) { return false }
            if allergensLower.contains(lower) { return false }
        }

        return true
    }
}
