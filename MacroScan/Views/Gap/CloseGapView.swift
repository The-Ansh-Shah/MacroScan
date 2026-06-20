import SwiftUI
import SwiftData

/// Non-AI "what should I eat?" view.
/// Shows remaining targets and suggests foods from the user's personal DB
/// that best close the biggest nutritional gap.
struct CloseGapView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \LogEntry.loggedAt, order: .reverse)
    private var allEntries: [LogEntry]

    @Query(sort: \Food.timesLogged, order: .reverse)
    private var allFoods: [Food]

    @Query private var profiles: [UserProfile]

    @Query(sort: \Recipe.timesUsed, order: .reverse)
    private var allRecipes: [Recipe]

    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case food(Food)
        case recipe(Recipe)
        case generate
        var id: String {
            switch self {
            case .food(let f): return "food-\(f.persistentModelID.hashValue)"
            case .recipe(let r): return "recipe-\(r.persistentModelID.hashValue)"
            case .generate: return "generate"
            }
        }
    }

    private var profile: UserProfile? { profiles.first }

    private var todayTotals: ScaledMacros {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return allEntries
            .filter { $0.loggedAt >= startOfToday }
            .reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
    }

    private var suggestions: [Food] {
        guard let profile else { return [] }
        let base = MealRanker.closeGapSuggestions(
            foods: allFoods,
            currentTotals: todayTotals,
            profile: profile,
            limit: 12
        )
        // Stored veg flags are unreliable for search-imported foods (they default to
        // isVegetarian = true), so add a conservative name guard for vegetarians.
        guard profile.isVegetarian else { return Array(base.prefix(10)) }
        return Array(base.filter { !Self.looksNonVegetarian($0.name) }.prefix(10))
    }

    private static func looksNonVegetarian(_ name: String) -> Bool {
        let n = name.lowercased()
        let meats = ["chicken", "beef", "pork", "bacon", "turkey", "sausage", "steak",
                     "lamb", "salmon", "tuna", "shrimp", "prawn", "anchov", "fish",
                     "tilapia", "sardine", "pepperoni", "prosciutto", "ham"]
        return meats.contains { n.contains($0) }
    }

    /// Saved recipes that fit the remaining calorie budget, ranked by protein.
    private var fittingRecipes: [Recipe] {
        guard let profile else { return [] }
        let calGap = max(0, profile.calorieTarget - todayTotals.calories)
        guard calGap > 0 else { return [] }
        return allRecipes
            .filter { $0.perServingMacros.proteinG > 0 && $0.perServingMacros.calories <= calGap + 100 }
            .sorted { $0.perServingMacros.proteinG > $1.perServingMacros.proteinG }
            .prefix(5)
            .map { $0 }
    }

    /// Bundled vegetarian high-protein library, ranked by protein density.
    /// Always browsable so the view is useful even before the user has logged much.
    private var curatedPicks: [Food] {
        guard let profile else { return [] }
        return allFoods
            .filter { $0.source == .curated && $0.isAllowed(for: profile) }
            .sorted { ($0.proteinG / max($0.calories, 1)) > ($1.proteinG / max($1.calories, 1)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if let profile {
                        gapSummaryCard(profile: profile)
                    }

                    generateButton

                    if !fittingRecipes.isEmpty {
                        recipesSection
                    }

                    if suggestions.isEmpty {
                        if !allFoods.isEmpty && curatedPicks.isEmpty {
                            EmptyStateView(
                                symbol: "checkmark.circle",
                                message: "You're close to your targets!"
                            )
                            .padding(.top, Spacing.lg)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("From your foods")
                                .font(.mHeadline)
                                .foregroundStyle(Color.mTextPrimary)

                            ForEach(suggestions) { food in
                                Button {
                                    activeSheet = .food(food)
                                } label: {
                                    FoodRow(
                                        name: food.name,
                                        detail: food.brand ?? "\(Int(food.servingSizeGrams))g serving",
                                        calories: Int(food.calories),
                                        proteinG: Int(food.proteinG),
                                        showChevron: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                                .fill(Color.mBgSecondary)
                        )
                    }

                    if !curatedPicks.isEmpty {
                        curatedSection
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .navigationTitle("Close the Gap")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .food(let food): ScanResultSheet(food: food)
                case .recipe(let recipe): LogRecipeSheet(recipe: recipe)
                case .generate: GenerateRecipeSheet()
                }
            }
        }
    }

    // MARK: - Generate a recipe

    private var generateButton: some View {
        Button {
            activeSheet = .generate
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Generate a recipe for this gap")
                        .font(.mHeadline)
                    Text("AI builds a vegetarian recipe that fits your remaining macros.")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextTertiary)
            }
            .foregroundStyle(Color.mAccent)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                    .fill(Color.mBgSecondary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fitting recipes

    @ViewBuilder
    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recipes that fit")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            ForEach(fittingRecipes) { recipe in
                Button {
                    activeSheet = .recipe(recipe)
                } label: {
                    let m = recipe.perServingMacros
                    FoodRow(
                        name: recipe.name,
                        detail: "\(formattedServings(recipe.totalServings)) serving\(recipe.totalServings == 1 ? "" : "s")",
                        calories: Int(m.calories),
                        proteinG: Int(m.proteinG),
                        showChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    private func formattedServings(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    // MARK: - Curated picks

    @ViewBuilder
    private var curatedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Vegetarian high-protein picks")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)
            Text("Lean, egg- & mushroom-free options ranked by protein per calorie.")
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)

            ForEach(curatedPicks) { food in
                Button {
                    activeSheet = .food(food)
                } label: {
                    FoodRow(
                        name: food.name,
                        detail: "\(Int(food.servingSizeGrams))g serving",
                        calories: Int(food.calories),
                        proteinG: Int(food.proteinG),
                        showChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    // MARK: - Gap Summary

    @ViewBuilder
    private func gapSummaryCard(profile: UserProfile) -> some View {
        let calGap = max(0, profile.calorieTarget - todayTotals.calories)
        let proGap = max(0, profile.proteinTargetG - todayTotals.proteinG)
        let fibGap = max(0, profile.fiberTargetG - todayTotals.fiberG)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Still Need Today")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            HStack(spacing: Spacing.md) {
                gapItem(label: "Calories", remaining: calGap, unit: "cal", atTarget: calGap <= 0)
                gapItem(label: "Protein", remaining: proGap, unit: "g", atTarget: proGap <= 0)
                gapItem(label: "Fiber", remaining: fibGap, unit: "g", atTarget: fibGap <= 0)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    private func gapItem(label: String, remaining: Double, unit: String, atTarget: Bool) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(atTarget ? "0" : "\(Int(remaining))")
                .font(.mStatNumber)
                .foregroundStyle(atTarget ? Color.mOnTarget : Color.mTextPrimary)
            Text("\(unit) \(label.lowercased())")
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
