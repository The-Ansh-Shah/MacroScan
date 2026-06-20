import SwiftUI
import SwiftData

enum QuickLogItem: Identifiable {
    case food(Food)
    case recipe(Recipe)

    var id: String {
        switch self {
        case .food(let f): return "food-\(f.persistentModelID.hashValue)"
        case .recipe(let r): return "recipe-\(r.persistentModelID.hashValue)"
        }
    }

    var name: String {
        switch self {
        case .food(let f): return f.name
        case .recipe(let r): return r.name
        }
    }

    var calories: Double {
        switch self {
        case .food(let f): return f.calories
        case .recipe(let r): return r.perServingMacros.calories
        }
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .recipe: return "book.closed.fill"
        }
    }
}

struct QuickLogBar: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Food.timesLogged, order: .reverse)
    private var allFoods: [Food]
    @Query(sort: \Recipe.timesUsed, order: .reverse)
    private var allRecipes: [Recipe]

    @State private var selectedFood: Food?
    @State private var selectedRecipe: Recipe?

    private var items: [QuickLogItem] {
        let topFoods = MealRanker.rank(foods: allFoods, limit: 4)
            .map { QuickLogItem.food($0) }
        let topRecipes = allRecipes
            .filter { $0.timesUsed > 0 }
            .prefix(2)
            .map { QuickLogItem.recipe($0) }
        return (topFoods + topRecipes).prefix(6).map { $0 }
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Quick Log")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(items) { item in
                            Button {
                                handleTap(item)
                            } label: {
                                VStack(spacing: Spacing.xs) {
                                    HStack(spacing: Spacing.xs) {
                                        if case .recipe = item {
                                            Image(systemName: "book.closed.fill")
                                                .font(.system(size: 8))
                                                .foregroundStyle(Color.mAccent)
                                        }
                                        Text(item.name)
                                            .font(.mCaption)
                                            .foregroundStyle(Color.mTextPrimary)
                                            .lineLimit(1)
                                    }
                                    Text("\(Int(item.calories)) cal")
                                        .font(.mCaption)
                                        .foregroundStyle(Color.mTextTertiary)
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.mBgSecondary)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if case .food(let f) = item {
                                    Button {
                                        selectedFood = f
                                    } label: {
                                        Label("Adjust amount & log…", systemImage: "slider.horizontal.3")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedFood) { food in
                ScanResultSheet(food: food)
            }
            .sheet(item: $selectedRecipe) { recipe in
                LogRecipeSheet(recipe: recipe)
            }
        }
    }

    private func handleTap(_ item: QuickLogItem) {
        switch item {
        case .food(let f):
            // One-tap re-log at one serving; long-press (contextMenu) adjusts the amount.
            let repo = FoodRepository(modelContext: modelContext)
            repo.logFood(f, grams: f.servingSizeGrams, mealType: repo.suggestedMealType(), servings: 1)
            Haptics.logFood()
        case .recipe(let r):
            selectedRecipe = r
        }
    }
}
