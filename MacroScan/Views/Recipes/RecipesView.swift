import SwiftUI
import SwiftData

struct RecipesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.lastUsedAt, order: .reverse)
    private var recipes: [Recipe]

    @State private var searchQuery: String = ""
    @State private var showingBuilder = false
    @State private var showingGenerator = false
    @State private var editingRecipe: Recipe?

    private var sorted: [Recipe] {
        recipes.sorted { ($0.isFavorite ? 0 : 1) < ($1.isFavorite ? 0 : 1) }
    }

    private var filtered: [Recipe] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    EmptyStateView(
                        symbol: "book.closed",
                        message: "No recipes yet.\nCombine foods into a meal you can log with one tap.",
                        buttonTitle: "New Recipe",
                        action: { showingBuilder = true }
                    )
                } else {
                    List {
                        ForEach(filtered) { recipe in
                            NavigationLink {
                                RecipeDetailView(recipe: recipe)
                            } label: {
                                recipeRow(recipe)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    let repo = FoodRepository(modelContext: modelContext)
                                    repo.deleteRecipe(recipe)
                                    Haptics.deleted()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    recipe.isFavorite.toggle()
                                    Haptics.selectionChanged()
                                } label: {
                                    Label(
                                        recipe.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: recipe.isFavorite ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.mApproaching)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchQuery, prompt: "Search recipes")
                }
            }
            .navigationTitle("My Recipes")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingBuilder = true
                        } label: {
                            Label("New Recipe", systemImage: "square.and.pencil")
                        }
                        Button {
                            showingGenerator = true
                        } label: {
                            Label("Generate with AI", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingBuilder) {
                RecipeBuilderView()
            }
            .sheet(isPresented: $showingGenerator) {
                GenerateRecipeSheet()
            }
        }
    }

    @ViewBuilder
    private func recipeRow(_ recipe: Recipe) -> some View {
        let macros = recipe.perServingMacros
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    if recipe.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color.mApproaching)
                            .font(.mCaption)
                    }
                    Text(recipe.name)
                        .font(.mBody)
                        .foregroundStyle(Color.mTextPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: Spacing.xs) {
                    Text("\(recipe.ingredients.count) ingredients")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                    Text("·")
                        .foregroundStyle(Color.mTextTertiary)
                    Text("\(formattedServings(recipe.totalServings)) serving\(recipe.totalServings == 1 ? "" : "s")")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("\(Int(macros.calories)) cal")
                    .font(.mBody)
                    .foregroundStyle(Color.mTextPrimary)
                Text("\(Int(macros.proteinG))g P")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
            }
        }
        .frame(minHeight: DesignConstants.minTapTarget)
    }

    private func formattedServings(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
