import SwiftUI
import SwiftData

struct ScanResultSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let food: Food
    var isVerified: Bool = false
    var afterLog: (() -> Void)? = nil

    @State private var amountText: String = ""
    @State private var useServings: Bool = false
    @State private var selectedMealType: MealType = .lunch
    @State private var notes: String = ""

    // Ingredient substitution state
    @State private var substitutions: [String: Food] = [:]
    @State private var replacingIngredient: String?
    @State private var showingIngredientSearch = false
    @State private var ingredientsExpanded = false

    // Phase 38: Nutrition editing state
    @State private var nutritionEditExpanded: Bool = false
    @State private var editCalories: String = ""
    @State private var editProtein: String = ""
    @State private var editCarbs: String = ""
    @State private var editFat: String = ""
    @State private var editFiber: String = ""
    // Captured once on appear so Reset always goes back to the initial display values
    @State private var origCal: String = ""
    @State private var origPro: String = ""
    @State private var origCarbs: String = ""
    @State private var origFat: String = ""
    @State private var origFiber: String = ""

    private var gramsEaten: Double {
        let raw = Double(amountText) ?? 0
        if useServings && food.servingSizeGrams > 0 {
            return raw * food.servingSizeGrams
        }
        return raw
    }

    // Effective per-serving macros, reflecting any edits made in the nutrition section
    private var effectiveMacrosPerServing: ScaledMacros {
        ScaledMacros(
            calories: Double(editCalories) ?? food.calories,
            proteinG: Double(editProtein) ?? food.proteinG,
            carbsG: Double(editCarbs) ?? food.carbsG,
            fatG: Double(editFat) ?? food.fatG,
            fiberG: Double(editFiber) ?? food.fiberG,
            ironMg: 0,
            vitaminDMcg: 0,
            vitaminB12Mcg: 0
        )
    }

    private var isNutritionModified: Bool {
        editCalories != origCal || editProtein != origPro ||
        editCarbs != origCarbs || editFat != origFat ||
        editFiber != origFiber
    }

    private var adjustedMacros: ScaledMacros? {
        let grams = gramsEaten
        guard grams > 0, food.servingSizeGrams > 0 else { return nil }
        let ratio = grams / food.servingSizeGrams
        let perServing = effectiveMacrosPerServing
        let base = ScaledMacros(
            calories: perServing.calories * ratio,
            proteinG: perServing.proteinG * ratio,
            carbsG: perServing.carbsG * ratio,
            fatG: perServing.fatG * ratio,
            fiberG: perServing.fiberG * ratio,
            ironMg: 0,
            vitaminDMcg: 0,
            vitaminB12Mcg: 0
        )
        guard !substitutions.isEmpty, !food.ingredients.isEmpty else { return base }

        let share = 1.0 / Double(food.ingredients.count)
        var adjusted = base
        for (_, replacement) in substitutions {
            let gramShare = grams * share
            let displaced = ScaledMacros(
                calories: base.calories * share,
                proteinG: base.proteinG * share,
                carbsG: base.carbsG * share,
                fatG: base.fatG * share,
                fiberG: base.fiberG * share,
                ironMg: 0,
                vitaminDMcg: 0,
                vitaminB12Mcg: 0
            )
            let added = replacement.macros(forGrams: gramShare)
            adjusted = ScaledMacros(
                calories: adjusted.calories - displaced.calories + added.calories,
                proteinG: adjusted.proteinG - displaced.proteinG + added.proteinG,
                carbsG: adjusted.carbsG - displaced.carbsG + added.carbsG,
                fatG: adjusted.fatG - displaced.fatG + added.fatG,
                fiberG: adjusted.fiberG - displaced.fiberG + added.fiberG,
                ironMg: 0,
                vitaminDMcg: 0,
                vitaminB12Mcg: 0
            )
        }
        return adjusted
    }

    var body: some View {
        NavigationStack {
            Form {
                // Phase 39: Verified banner
                if isVerified {
                    Section {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.mOnTarget)
                            Text("You've verified this food before. Macros shown are your saved values.")
                                .font(.mCaption)
                                .foregroundStyle(Color.mTextSecondary)
                        }
                    }
                    .listRowBackground(Color.mBgSecondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(food.name)
                            .font(.mTitle3)
                            .foregroundStyle(Color.mTextPrimary)

                        if let brand = food.brand {
                            Text(brand)
                                .font(.mSubheadline)
                                .foregroundStyle(Color.mTextSecondary)
                        }
                    }
                }

                Section("Amount") {
                    AmountPicker(
                        servingSizeGrams: food.servingSizeGrams > 0 ? food.servingSizeGrams : nil,
                        inputText: $amountText,
                        useServings: $useServings
                    )
                }

                Section("Meal") {
                    Picker("Meal", selection: $selectedMealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedMealType) { _, _ in
                        Haptics.selectionChanged()
                    }
                }

                if !food.ingredients.isEmpty {
                    ingredientsSection
                }

                // Phase 38: Editable nutrition disclosure section
                nutritionEditSection

                if let macros = adjustedMacros {
                    Section("Nutrition") {
                        if !substitutions.isEmpty {
                            Label("Approximate — based on typical ingredient values", systemImage: "info.circle")
                                .font(.mCaption)
                                .foregroundStyle(Color.mTextTertiary)
                        }
                        nutritionRow("Calories", value: macros.calories, unit: "cal")
                        nutritionRow("Protein", value: macros.proteinG, unit: "g")
                        nutritionRow("Carbs", value: macros.carbsG, unit: "g")
                        nutritionRow("Fat", value: macros.fatG, unit: "g")
                        nutritionRow("Fiber", value: macros.fiberG, unit: "g")
                    }
                }

                Section("Notes (optional)") {
                    TextField("e.g. substitutions, extras, how it tasted", text: $notes, axis: .vertical)
                        .font(.mBody)
                        .lineLimit(2...5)
                }

                if food.containsEggs || food.containsMushrooms {
                    Section {
                        if food.containsEggs {
                            Label("Contains eggs", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Color.mApproaching)
                        }
                        if food.containsMushrooms {
                            Label("Contains mushrooms", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Color.mApproaching)
                        }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Log Food")
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
                        logEntry()
                    }
                    .bold()
                    .disabled(gramsEaten <= 0)
                }
            }
            .onAppear { setupDefaults() }
            .sheet(isPresented: $showingIngredientSearch) {
                IngredientSubstitutePicker { replacement in
                    if let original = replacingIngredient {
                        substitutions[original.lowercased()] = replacement
                    }
                    replacingIngredient = nil
                    showingIngredientSearch = false
                }
            }
        }
    }

    // MARK: - Nutrition edit section (Phase 38)

    @ViewBuilder
    private var nutritionEditSection: some View {
        let servingLabel = food.servingSizeGrams > 0 ? "\(Int(food.servingSizeGrams))g" : "serving"
        Section {
            DisclosureGroup(isExpanded: $nutritionEditExpanded) {
                macroEditRow("Calories", binding: $editCalories, unit: "cal")
                macroEditRow("Protein", binding: $editProtein, unit: "g")
                macroEditRow("Carbs", binding: $editCarbs, unit: "g")
                macroEditRow("Fat", binding: $editFat, unit: "g")
                macroEditRow("Fiber", binding: $editFiber, unit: "g")

                Button("Reset to scanned values") {
                    resetNutrition()
                }
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
            } label: {
                HStack {
                    Text("Nutrition (per \(servingLabel))")
                        .font(.mBody)
                        .foregroundStyle(Color.mTextPrimary)
                    Spacer()
                    if isNutritionModified {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(Color.mAccent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func macroEditRow(_ label: String, binding: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label).font(.mBody)
            Spacer()
            TextField("0", text: binding)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
                .font(.mBody)
            Text(unit)
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    // MARK: - Ingredients section

    @ViewBuilder
    private var ingredientsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $ingredientsExpanded) {
                ForEach(food.ingredients, id: \.self) { ingredient in
                    ingredientRow(ingredient)
                }
            } label: {
                HStack {
                    Label("Customize ingredients", systemImage: "slider.horizontal.3")
                        .font(.mBody)
                    Spacer()
                    if !substitutions.isEmpty {
                        Text("\(substitutions.count) swap\(substitutions.count == 1 ? "" : "s")")
                            .font(.mCaption)
                            .foregroundStyle(Color.mAccent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ingredientRow(_ ingredient: String) -> some View {
        let key = ingredient.lowercased()
        let replacement = substitutions[key]

        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    if replacement != nil {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color.mAccent)
                            .font(.mCaption)
                    }
                    Text(ingredient)
                        .font(.mBody)
                        .foregroundStyle(replacement == nil ? Color.mTextPrimary : Color.mTextTertiary)
                        .strikethrough(replacement != nil)
                }
                if let replacement {
                    Text("→ \(replacement.name)")
                        .font(.mCaption)
                        .foregroundStyle(Color.mAccent)
                }
            }
            Spacer()
            if replacement == nil {
                Button("Replace") {
                    replacingIngredient = ingredient
                    showingIngredientSearch = true
                }
                .font(.mCaption)
                .buttonStyle(.bordered)
            } else {
                Button {
                    substitutions.removeValue(forKey: key)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(Color.mTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func nutritionRow(_ label: String, value: Double, unit: String) -> some View {
        HStack {
            Text(label)
                .font(.mBody)
            Spacer()
            Text("\(unit == "cal" ? "\(Int(value))" : String(format: "%.1f", value)) \(unit)")
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
        }
    }

    // MARK: - Actions

    private func logEntry() {
        let grams = gramsEaten
        guard grams > 0 else { return }
        let servings: Double? = useServings && food.servingSizeGrams > 0 ? (Double(amountText) ?? nil) : nil
        let repo = FoodRepository(modelContext: modelContext)

        let userNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if !userNotes.isEmpty { lines.append(userNotes) }
        if !substitutions.isEmpty {
            let swaps = substitutions
                .map { "\($0.key) → \($0.value.name)" }
                .sorted()
                .joined(separator: ", ")
            lines.append("swapped: \(swaps)")
        }
        let combinedNotes = lines.isEmpty ? nil : lines.joined(separator: "\n")

        let logFood: Food
        if isNutritionModified {
            // Phase 38/39: apply edited macros directly to the food record and mark as verified
            food.calories = Double(editCalories) ?? food.calories
            food.proteinG = Double(editProtein) ?? food.proteinG
            food.carbsG = Double(editCarbs) ?? food.carbsG
            food.fatG = Double(editFat) ?? food.fatG
            food.fiberG = Double(editFiber) ?? food.fiberG
            food.userVerified = true
            food.lastVerifiedAt = Date()
            logFood = food
        } else if !substitutions.isEmpty, let adjusted = adjustedMacros {
            let scale = food.servingSizeGrams / grams
            let derived = Food(
                name: "\(food.name) (customized)",
                brand: food.brand,
                servingSizeGrams: food.servingSizeGrams,
                calories: adjusted.calories * scale,
                proteinG: adjusted.proteinG * scale,
                carbsG: adjusted.carbsG * scale,
                fatG: adjusted.fatG * scale,
                fiberG: adjusted.fiberG * scale,
                source: .manual,
                isVegetarian: food.isVegetarian,
                containsEggs: food.containsEggs,
                containsMushrooms: food.containsMushrooms
            )
            repo.save(food: derived)
            logFood = derived
        } else {
            logFood = food
        }

        repo.logFood(logFood, grams: grams, mealType: selectedMealType, servings: servings, notes: combinedNotes)
        Haptics.logFood()
        dismiss()
        afterLog?()
    }

    private func setupDefaults() {
        selectedMealType = .currentGuess
        if food.servingSizeGrams > 0 {
            useServings = true
            amountText = "1"
        } else {
            useServings = false
            amountText = "100"
        }
        // Capture initial nutrition values as display strings
        origCal   = String(format: "%.0f", food.calories)
        origPro   = String(format: "%.1f", food.proteinG)
        origCarbs = String(format: "%.1f", food.carbsG)
        origFat   = String(format: "%.1f", food.fatG)
        origFiber = String(format: "%.1f", food.fiberG)
        // Init edit fields to match
        editCalories  = origCal
        editProtein   = origPro
        editCarbs     = origCarbs
        editFat       = origFat
        editFiber     = origFiber
    }

    private func resetNutrition() {
        editCalories  = origCal
        editProtein   = origPro
        editCarbs     = origCarbs
        editFat       = origFat
        editFiber     = origFiber
    }
}

// MARK: - Ingredient substitute picker

/// Lightweight search over the local food library. Picks a replacement ingredient for a swap.
private struct IngredientSubstitutePicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.timesLogged, order: .reverse) private var allFoods: [Food]

    @State private var query: String = ""
    let onPick: (Food) -> Void

    private var filtered: [Food] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Array(allFoods.prefix(20)) }
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
                        message: "No local foods match. Log the substitute once manually to use it here."
                    )
                } else {
                    List(filtered) { food in
                        Button {
                            onPick(food)
                            Haptics.selectionChanged()
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(food.name).font(.mBody).foregroundStyle(Color.mTextPrimary)
                                if let brand = food.brand, !brand.isEmpty {
                                    Text(brand).font(.mCaption).foregroundStyle(Color.mTextSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pick Substitute")
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
