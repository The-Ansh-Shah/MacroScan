import SwiftUI
import SwiftData

/// AI-powered, goal-aware vegetarian recipe generator.
/// Three phases mirror `AIEstimateSheet`: input → generating → review.
/// In "Fit my macros" mode it passes the user's remaining calories/protein for the day;
/// in "Free-form" mode it passes nil and lets keywords drive the result.
struct GenerateRecipeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    enum Phase { case input, generating, review }
    enum Mode: String, CaseIterable, Identifiable {
        case fitMacros = "Fit my macros"
        case freeForm = "Free-form"
        var id: String { rawValue }
    }

    @State private var phase: Phase = .input
    @State private var mode: Mode = .fitMacros
    @State private var keywords: String = ""
    @State private var errorMessage: String?

    // Populated once the recipe arrives
    @State private var recipe: AIVisionService.GeneratedRecipe?
    @State private var recipeName: String = ""

    private let vision = AIVisionService()

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input: inputView
                case .generating: generatingView
                case .review: reviewView
                }
            }
            .navigationTitle("Generate Recipe")
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
                if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .bold()
                            .disabled(recipeName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Input phase

    private var inputView: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in Haptics.selectionChanged() }
            }

            Section {
                TextField("Keywords or cuisine (e.g. high-protein, Indian)", text: $keywords)
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("What do you want?")
            } footer: {
                if mode == .fitMacros, let remaining = remainingTargets {
                    Text("Will aim for ~\(Int(remaining.calories)) kcal and ~\(Int(remaining.protein)) g protein per serving (your remaining for today).")
                } else if mode == .fitMacros {
                    Text("Set up your profile targets to use this mode.")
                } else {
                    Text("Free-form: a recipe based purely on your keywords.")
                }
            }

            Section {
                PrimaryButton("Generate", icon: "sparkles") {
                    Task { await generate() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .keyboardDoneButton()
    }

    // MARK: - Generating phase

    private var generatingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .controlSize(.large)
            Text("Generating your recipe…")
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    // MARK: - Review phase

    private var reviewView: some View {
        Form {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.mOver)
                        .font(.mSubheadline)
                    Button("Try again") {
                        phase = .input
                        self.errorMessage = nil
                    }
                    .font(.mBody)
                    .foregroundStyle(Color.mAccent)
                }
            }

            if let recipe {
                Section {
                    TextField("Recipe name", text: $recipeName)
                        .font(.mHeadline)
                    Text("\(formattedServings(recipe.totalServings)) serving\(recipe.totalServings == 1 ? "" : "s")")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                    if let notes = recipe.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.mSubheadline)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                }

                Section("Per serving") {
                    let m = perServing(recipe)
                    macroRow("Calories", "\(Int(m.calories)) cal")
                    macroRow("Protein", "\(Int(m.proteinG)) g")
                    macroRow("Carbs", "\(Int(m.carbsG)) g")
                    macroRow("Fat", "\(Int(m.fatG)) g")
                    macroRow("Fiber", "\(Int(m.fiberG)) g")
                }

                Section("Ingredients") {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, ing in
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(ing.name)
                                    .font(.mBody)
                                    .foregroundStyle(Color.mTextPrimary)
                                Text("\(Int(ing.grams)) g")
                                    .font(.mCaption)
                                    .foregroundStyle(Color.mTextSecondary)
                            }
                            Spacer()
                            Text("\(Int(ing.calories)) cal")
                                .font(.mCaption)
                                .foregroundStyle(Color.mTextSecondary)
                        }
                        .frame(minHeight: DesignConstants.minTapTarget)
                    }
                }
            }
        }
        .keyboardDoneButton()
    }

    @ViewBuilder
    private func macroRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.mBody)
            Spacer()
            Text(value)
                .font(.mBody)
                .monospacedDigit()
                .foregroundStyle(Color.mTextSecondary)
        }
    }

    // MARK: - Logic

    /// Remaining calories/protein for today, floored at small positive values
    /// so we never ask the model for a zero/negative-target recipe.
    private var remainingTargets: (calories: Double, protein: Double)? {
        guard let profile else { return nil }
        let totals = FoodRepository(modelContext: modelContext).dailyTotals(forDate: Date())
        let cals = max(profile.calorieTarget - totals.calories, 200)
        let protein = max(profile.proteinTargetG - totals.proteinG, 10)
        return (cals, protein)
    }

    private func perServing(_ recipe: AIVisionService.GeneratedRecipe) -> ScaledMacros {
        let servings = recipe.totalServings > 0 ? recipe.totalServings : 1
        let total = recipe.ingredients.reduce(ScaledMacros.zero) { sum, ing in
            sum + ScaledMacros(
                calories: ing.calories,
                proteinG: ing.proteinG,
                carbsG: ing.carbsG,
                fatG: ing.fatG,
                fiberG: ing.fiberG,
                ironMg: 0, vitaminDMcg: 0, vitaminB12Mcg: 0
            )
        }
        let scale = 1.0 / servings
        return ScaledMacros(
            calories: total.calories * scale,
            proteinG: total.proteinG * scale,
            carbsG: total.carbsG * scale,
            fatG: total.fatG * scale,
            fiberG: total.fiberG * scale,
            ironMg: 0, vitaminDMcg: 0, vitaminB12Mcg: 0
        )
    }

    private func generate() async {
        phase = .generating
        errorMessage = nil

        let vegetarian = profile?.isVegetarian ?? true
        let exclusions = profile?.excludedIngredients ?? ["eggs", "mushrooms"]
        let targets: (calories: Double, protein: Double)? = mode == .fitMacros ? remainingTargets : nil

        // Telemetry (best-effort).
        if let profile {
            profile.aiCallsTotal += 1
        }

        do {
            let result = try await vision.generateRecipe(
                prompt: keywords,
                isVegetarian: vegetarian,
                excludedIngredients: exclusions,
                targetCalories: targets?.calories,
                targetProtein: targets?.protein
            )
            await MainActor.run {
                recipe = result
                recipeName = result.name
                phase = .review
            }
        } catch {
            await MainActor.run {
                if let aiError = error as? AIVisionService.AIError,
                   AIVisionService.isQuotaError(aiError) {
                    errorMessage = "AI is temporarily rate-limited. This usually resolves within a few minutes."
                    if let profile {
                        profile.aiQuotaErrorsTotal += 1
                        profile.aiLastErrorAt = Date()
                    }
                } else {
                    errorMessage = error.localizedDescription
                }
                // Land on review phase to surface the error + a retry affordance.
                recipe = nil
                phase = .review
            }
        }
    }

    /// Build Foods + Recipe + RecipeIngredients exactly like `SeedLibrary`.
    /// Each ingredient Food's `servingSizeGrams` == its grams and macros are AT that
    /// gram amount, so `macros(forGrams: grams)` returns them with ratio 1 and
    /// `Recipe.perServingMacros` computes correctly.
    private func save() {
        guard let recipe else { return }
        let trimmedName = recipeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let servings = recipe.totalServings > 0 ? recipe.totalServings : 1

        let newRecipe = Recipe(
            name: trimmedName.isEmpty ? recipe.name : trimmedName,
            notes: recipe.notes,
            totalServings: servings
        )
        modelContext.insert(newRecipe)

        for (idx, ing) in recipe.ingredients.enumerated() {
            let grams = ing.grams > 0 ? ing.grams : 1
            let food = Food(
                name: ing.name,
                servingSizeGrams: grams,
                calories: ing.calories,
                proteinG: ing.proteinG,
                carbsG: ing.carbsG,
                fatG: ing.fatG,
                fiberG: ing.fiberG,
                source: .aiRecipe,
                isVegetarian: true,
                containsEggs: false,
                containsMushrooms: false
            )
            modelContext.insert(food)

            let recipeIngredient = RecipeIngredient(food: food, grams: grams, order: idx)
            recipeIngredient.recipe = newRecipe
            modelContext.insert(recipeIngredient)
            newRecipe.ingredients.append(recipeIngredient)
        }

        FoodRepository(modelContext: modelContext).saveRecipe(newRecipe)
        Haptics.logFood()
        dismiss()
    }

    private func formattedServings(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
