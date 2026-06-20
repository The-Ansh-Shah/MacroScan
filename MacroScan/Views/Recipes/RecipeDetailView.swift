import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe

    @State private var activeSheet: ActiveSheet?
    @State private var showingDeleteConfirm = false

    private enum ActiveSheet: Identifiable {
        case log, edit
        var id: Int { self == .log ? 0 : 1 }
    }

    var body: some View {
        List {
            Section {
                macroSummary
            } header: {
                Text("Per Serving (\(formattedServings(recipe.totalServings)) total)")
            }

            Section {
                ForEach(
                    recipe.ingredients.sorted(by: { $0.order < $1.order })
                ) { ingredient in
                    ingredientRow(ingredient)
                }
            } header: {
                Text("Ingredients")
            }

            if !recipe.instructions.isEmpty {
                Section("Instructions") {
                    Text(recipe.instructions)
                        .font(.mBody)
                        .foregroundStyle(Color.mTextPrimary)
                        .lineSpacing(3)
                }
            }

            if let notes = recipe.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }

            Section {
                HStack {
                    Text("Created")
                        .font(.mBody)
                    Spacer()
                    Text(recipe.createdAt, style: .date)
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                }
                HStack {
                    Text("Times used")
                        .font(.mBody)
                    Spacer()
                    Text("\(recipe.timesUsed)")
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                        .monospacedDigit()
                }
                if let lastUsed = recipe.lastUsedAt {
                    HStack {
                        Text("Last used")
                            .font(.mBody)
                        Spacer()
                        Text(lastUsed, style: .relative)
                            .font(.mBody)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                }
            }
        }
        .navigationTitle(recipe.name)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { activeSheet = .log } label: {
                        Label("Log This", systemImage: "plus.circle")
                    }
                    Button { activeSheet = .edit } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) { showingDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .log: LogRecipeSheet(recipe: recipe)
            case .edit: RecipeBuilderView(existingRecipe: recipe)
            }
        }
        .alert("Delete Recipe?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                let repo = FoodRepository(modelContext: modelContext)
                repo.deleteRecipe(recipe)
                Haptics.deleted()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete \"\(recipe.name)\". Past log entries are not affected.")
        }
    }

    private var macroSummary: some View {
        let m = recipe.perServingMacros
        return HStack(spacing: Spacing.md) {
            macroChip("Cal", value: m.calories)
            macroChip("P", value: m.proteinG, suffix: "g")
            macroChip("C", value: m.carbsG, suffix: "g")
            macroChip("F", value: m.fatG, suffix: "g")
            macroChip("Fiber", value: m.fiberG, suffix: "g")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
    }

    private func macroChip(_ label: String, value: Double, suffix: String = "") -> some View {
        VStack(spacing: Spacing.xs) {
            Text("\(Int(value))\(suffix)")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)
                .monospacedDigit()
            Text(label)
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
        }
    }

    @ViewBuilder
    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
        if let food = ingredient.food {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(food.name)
                        .font(.mBody)
                        .foregroundStyle(Color.mTextPrimary)
                    if let brand = food.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("\(Int(ingredient.grams))g")
                        .font(.mBody)
                        .foregroundStyle(Color.mTextTertiary)
                    let macros = food.macros(forGrams: ingredient.grams)
                    Text("\(Int(macros.calories)) cal")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }
        }
    }

    private func formattedServings(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - Log Recipe Sheet

struct LogRecipeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe

    @State private var servings: Double = 1
    @State private var selectedMealType: MealType = .lunch
    @State private var notes: String = ""

    private var scaledMacros: ScaledMacros {
        let m = recipe.perServingMacros
        return ScaledMacros(
            calories: m.calories * servings,
            proteinG: m.proteinG * servings,
            carbsG: m.carbsG * servings,
            fatG: m.fatG * servings,
            fiberG: m.fiberG * servings,
            ironMg: m.ironMg * servings,
            vitaminDMcg: m.vitaminDMcg * servings,
            vitaminB12Mcg: m.vitaminB12Mcg * servings
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(recipe.name)
                        .font(.mTitle3)
                        .foregroundStyle(Color.mTextPrimary)
                }

                Section("How much?") {
                    Stepper(
                        "Servings: \(formattedServings(servings))",
                        value: $servings,
                        in: 0.25...10,
                        step: 0.25
                    )
                    .font(.mBody)
                }

                Section("Meal") {
                    Picker("Meal", selection: $selectedMealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedMealType) { _, _ in
                        Haptics.selectionChanged()
                    }
                }

                Section("Nutrition") {
                    nutritionRow("Calories", value: scaledMacros.calories, unit: "cal")
                    nutritionRow("Protein", value: scaledMacros.proteinG, unit: "g")
                    nutritionRow("Carbs", value: scaledMacros.carbsG, unit: "g")
                    nutritionRow("Fat", value: scaledMacros.fatG, unit: "g")
                    nutritionRow("Fiber", value: scaledMacros.fiberG, unit: "g")
                }

                Section("Notes (optional)") {
                    TextField("e.g. added extra protein powder", text: $notes, axis: .vertical)
                        .font(.mBody)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Log Recipe")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.sheetDismissed()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        logIt()
                    }
                    .bold()
                    .disabled(servings <= 0)
                }
            }
            .onAppear { selectedMealType = .currentGuess }
        }
    }

    private func nutritionRow(_ label: String, value: Double, unit: String) -> some View {
        HStack {
            Text(label).font(.mBody)
            Spacer()
            Text("\(String(format: "%.1f", value)) \(unit)")
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
        }
    }

    private func logIt() {
        let repo = FoodRepository(modelContext: modelContext)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        repo.logRecipe(
            recipe,
            servings: servings,
            mealType: selectedMealType,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        Haptics.logFood()
        dismiss()
    }

    private func formattedServings(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
