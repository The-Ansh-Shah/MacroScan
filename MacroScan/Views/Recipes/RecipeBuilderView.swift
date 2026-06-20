import SwiftUI
import SwiftData

struct RecipeBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingRecipe: Recipe?

    @State private var name: String = ""
    @State private var totalServings: Double = 1
    @State private var notes: String = ""
    @State private var instructions: String = ""
    @State private var ingredients: [IngredientItem] = []
    @State private var showingFoodSearch = false
    @State private var pendingFoodForGrams: Food?
    @State private var gramsInput: String = ""

    struct IngredientItem: Identifiable {
        let id = UUID()
        let food: Food
        var grams: Double
    }

    private var perServingMacros: ScaledMacros {
        guard totalServings > 0 else { return .zero }
        let total = ingredients.reduce(ScaledMacros.zero) { sum, item in
            sum + item.food.macros(forGrams: item.grams)
        }
        let scale = 1.0 / totalServings
        return ScaledMacros(
            calories: total.calories * scale,
            proteinG: total.proteinG * scale,
            carbsG: total.carbsG * scale,
            fatG: total.fatG * scale,
            fiberG: total.fiberG * scale,
            ironMg: total.ironMg * scale,
            vitaminDMcg: total.vitaminDMcg * scale,
            vitaminB12Mcg: total.vitaminB12Mcg * scale
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !ingredients.isEmpty
        && totalServings > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Recipe name", text: $name)
                        .font(.mBody)
                    Stepper(
                        "Servings: \(formattedServings(totalServings))",
                        value: $totalServings,
                        in: 0.5...20,
                        step: 0.5
                    )
                    .font(.mBody)
                }

                Section {
                    macroSummaryRow
                } header: {
                    Text("Per Serving")
                }

                Section {
                    ForEach(ingredients) { item in
                        ingredientRow(item)
                    }
                    .onDelete { offsets in
                        ingredients.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        ingredients.move(fromOffsets: from, toOffset: to)
                    }

                    Button {
                        showingFoodSearch = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle")
                            .font(.mBody)
                    }
                } header: {
                    Text("Ingredients (\(ingredients.count))")
                }

                Section("Instructions (optional)") {
                    TextField("Step-by-step preparation", text: $instructions, axis: .vertical)
                        .font(.mBody)
                        .lineLimit(3...12)
                }

                Section("Notes (optional)") {
                    TextField("notes", text: $notes, axis: .vertical)
                        .font(.mBody)
                        .lineLimit(2...4)
                }
            }
            .keyboardDoneButton()
            .navigationTitle(existingRecipe == nil ? "New Recipe" : "Edit Recipe")
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
                    Button("Save") {
                        saveRecipe()
                    }
                    .bold()
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingFoodSearch) {
                RecipeIngredientPicker { food in
                    pendingFoodForGrams = food
                    gramsInput = "\(Int(food.servingSizeGrams))"
                    showingFoodSearch = false
                }
            }
            .alert("How many grams?", isPresented: Binding(
                get: { pendingFoodForGrams != nil },
                set: { if !$0 { pendingFoodForGrams = nil } }
            )) {
                TextField("grams", text: $gramsInput)
                    #if canImport(UIKit)
                    .keyboardType(.decimalPad)
                    #endif
                Button("Add") {
                    if let food = pendingFoodForGrams,
                       let grams = Double(gramsInput), grams > 0 {
                        ingredients.append(IngredientItem(food: food, grams: grams))
                        Haptics.logFood()
                    }
                    pendingFoodForGrams = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingFoodForGrams = nil
                }
            } message: {
                if let food = pendingFoodForGrams {
                    Text("\(food.name) — standard serving is \(Int(food.servingSizeGrams))g")
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private var macroSummaryRow: some View {
        let m = perServingMacros
        return HStack(spacing: Spacing.md) {
            macroChip("Cal", value: m.calories)
            macroChip("P", value: m.proteinG, suffix: "g")
            macroChip("C", value: m.carbsG, suffix: "g")
            macroChip("F", value: m.fatG, suffix: "g")
        }
        .frame(maxWidth: .infinity)
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
    private func ingredientRow(_ item: IngredientItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.food.name)
                    .font(.mBody)
                    .foregroundStyle(Color.mTextPrimary)
                    .lineLimit(1)
                if let brand = item.food.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }
            Spacer()
            Text("\(Int(item.grams))g")
                .font(.mBody)
                .foregroundStyle(Color.mTextTertiary)
        }
    }

    private func loadExisting() {
        guard let recipe = existingRecipe else { return }
        name = recipe.name
        totalServings = recipe.totalServings
        notes = recipe.notes ?? ""
        instructions = recipe.instructions
        ingredients = recipe.ingredients
            .sorted(by: { $0.order < $1.order })
            .compactMap { ing in
                guard let food = ing.food else { return nil }
                return IngredientItem(food: food, grams: ing.grams)
            }
    }

    private func saveRecipe() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !ingredients.isEmpty else { return }

        let repo = FoodRepository(modelContext: modelContext)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = existingRecipe {
            existing.name = trimmedName
            existing.totalServings = totalServings
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existing.instructions = trimmedInstructions
            for ing in existing.ingredients {
                modelContext.delete(ing)
            }
            existing.ingredients = ingredients.enumerated().map { idx, item in
                RecipeIngredient(food: item.food, grams: item.grams, order: idx)
            }
        } else {
            let recipe = Recipe(
                name: trimmedName,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                instructions: trimmedInstructions,
                totalServings: totalServings
            )
            recipe.ingredients = ingredients.enumerated().map { idx, item in
                RecipeIngredient(food: item.food, grams: item.grams, order: idx)
            }
            repo.saveRecipe(recipe)
        }

        Haptics.logFood()
        dismiss()
    }

    private func formattedServings(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - Ingredient Picker

private struct RecipeIngredientPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.timesLogged, order: .reverse) private var allFoods: [Food]

    @State private var query: String = ""
    let onPick: (Food) -> Void

    private var filtered: [Food] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Array(allFoods.prefix(30)) }
        return allFoods.filter {
            $0.name.lowercased().contains(q) ||
            ($0.brand?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.mTextTertiary)
                    TextField("Search your library…", text: $query)
                        .font(.mBody)
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                }
                .padding(Spacing.sm)
                .background(Color.mBgSecondary, in: RoundedRectangle(cornerRadius: 10))
                .padding(Spacing.md)

                if filtered.isEmpty {
                    EmptyStateView(
                        symbol: "questionmark.circle",
                        message: "No foods match. Log a food first, then add it as an ingredient."
                    )
                } else {
                    List(filtered) { food in
                        Button {
                            onPick(food)
                            Haptics.selectionChanged()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(food.name).font(.mBody).foregroundStyle(Color.mTextPrimary)
                                    if let brand = food.brand, !brand.isEmpty {
                                        Text(brand).font(.mCaption).foregroundStyle(Color.mTextSecondary)
                                    }
                                }
                                Spacer()
                                Text("\(Int(food.calories)) cal/\(Int(food.servingSizeGrams))g")
                                    .font(.mCaption)
                                    .foregroundStyle(Color.mTextTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pick Ingredient")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
