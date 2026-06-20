import SwiftUI
import SwiftData

/// AI-powered, goal-aware vegetarian recipe generator with editing + iterative tweaks.
///
/// Phases: input → generating → review. The review copy is FULLY editable — name,
/// servings, per-ingredient grams + macros, preparation instructions, and notes — and
/// can be refined by asking Gemini for a change ("make it spicier", "swap rice for
/// quinoa"), which regenerates the recipe from the current version. Saving builds a
/// `Recipe` + ingredient `Food`s exactly like the manual builder, so it lands in the
/// library and can be edited/deleted there too.
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

    struct EditableIngredient: Identifiable {
        let id = UUID()
        var name: String
        var grams: String
        var calories: String
        var proteinG: String
        var carbsG: String
        var fatG: String
        var fiberG: String
    }

    @State private var phase: Phase = .input
    @State private var mode: Mode = .fitMacros
    @State private var keywords = ""
    @State private var errorMessage: String?
    @State private var progressLabel = "Generating your recipe…"

    // Editable working copy (review phase)
    @State private var editName = ""
    @State private var editServings: Double = 1
    @State private var editNotes = ""
    @State private var editInstructions = ""
    @State private var editIngredients: [EditableIngredient] = []
    @State private var refineText = ""

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
                    Button("Cancel") { Haptics.sheetDismissed(); dismiss() }
                }
                if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .bold()
                            .disabled(!canSave)
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        !editName.trimmingCharacters(in: .whitespaces).isEmpty && !editIngredients.isEmpty
    }

    // MARK: - Input phase

    private var inputView: some View {
        Form {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.mSubheadline)
                        .foregroundStyle(Color.mOver)
                }
            }

            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
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
                if mode == .fitMacros, let r = remainingTargets {
                    Text("Will aim for ~\(Int(r.calories)) kcal and ~\(Int(r.protein)) g protein per serving (your remaining for today).")
                } else if mode == .fitMacros {
                    Text("Set up your profile targets to use this mode.")
                } else {
                    Text("Free-form: a recipe based purely on your keywords.")
                }
            }

            Section {
                PrimaryButton("Generate", icon: "sparkles") { Task { await generate() } }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .keyboardDoneButton()
    }

    // MARK: - Generating phase

    private var generatingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView().controlSize(.large)
            Text(progressLabel)
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    // MARK: - Review phase (editable)

    private var reviewView: some View {
        Form {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.mSubheadline)
                        .foregroundStyle(Color.mOver)
                }
            }

            Section("Recipe") {
                TextField("Recipe name", text: $editName).font(.mHeadline)
                Stepper("Servings: \(formattedServings(editServings))",
                        value: $editServings, in: 0.5...20, step: 0.5)
                    .font(.mBody)
            }

            Section("Per serving") {
                let m = perServing
                macroRow("Calories", "\(Int(m.calories)) cal")
                macroRow("Protein", "\(Int(m.proteinG)) g")
                macroRow("Carbs", "\(Int(m.carbsG)) g")
                macroRow("Fat", "\(Int(m.fatG)) g")
                macroRow("Fiber", "\(Int(m.fiberG)) g")
            }

            Section {
                TextField("e.g. make it spicier, swap rice for quinoa, add more protein",
                          text: $refineText, axis: .vertical)
                    .font(.mBody)
                    .lineLimit(1...3)
                Button {
                    Task { await refine() }
                } label: {
                    Label("Apply change with AI", systemImage: "wand.and.stars")
                        .font(.mBody)
                }
                .disabled(refineText.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Tweak this recipe")
            } footer: {
                Text("Asks AI to revise the current recipe. You can also edit any field below by hand.")
            }

            Section("Ingredients") {
                ForEach($editIngredients) { $ing in
                    ingredientEditor($ing)
                }
                .onDelete { editIngredients.remove(atOffsets: $0) }
            }

            Section("Instructions") {
                TextField("Step-by-step preparation", text: $editInstructions, axis: .vertical)
                    .font(.mBody)
                    .lineLimit(3...14)
            }

            Section("Notes (optional)") {
                TextField("notes", text: $editNotes, axis: .vertical)
                    .font(.mBody)
                    .lineLimit(1...4)
            }
        }
        .keyboardDoneButton()
    }

    @ViewBuilder
    private func ingredientEditor(_ ing: Binding<EditableIngredient>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField("Ingredient", text: ing.name)
                .font(.mBody)
                .foregroundStyle(Color.mTextPrimary)
            HStack(spacing: Spacing.sm) {
                numField("g", ing.grams)
                numField("cal", ing.calories)
                numField("P", ing.proteinG)
                numField("C", ing.carbsG)
                numField("F", ing.fatG)
                numField("Fib", ing.fiberG)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func numField(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(spacing: 2) {
            TextField("", text: binding)
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.center)
                .font(.mCaption)
                .monospacedDigit()
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.mTextTertiary)
        }
    }

    @ViewBuilder
    private func macroRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.mBody)
            Spacer()
            Text(value).font(.mBody).monospacedDigit().foregroundStyle(Color.mTextSecondary)
        }
    }

    // MARK: - Macro math

    private func dbl(_ s: String) -> Double { Double(s) ?? 0 }

    private var perServing: ScaledMacros {
        let servings = editServings > 0 ? editServings : 1
        let total = editIngredients.reduce(ScaledMacros.zero) { sum, ing in
            sum + ScaledMacros(
                calories: dbl(ing.calories),
                proteinG: dbl(ing.proteinG),
                carbsG: dbl(ing.carbsG),
                fatG: dbl(ing.fatG),
                fiberG: dbl(ing.fiberG),
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

    private var remainingTargets: (calories: Double, protein: Double)? {
        guard let profile else { return nil }
        let totals = FoodRepository(modelContext: modelContext).dailyTotals(forDate: Date())
        return (max(profile.calorieTarget - totals.calories, 200),
                max(profile.proteinTargetG - totals.proteinG, 10))
    }

    private func targetsForMode() -> (Double?, Double?) {
        guard mode == .fitMacros, let r = remainingTargets else { return (nil, nil) }
        return (r.calories, r.protein)
    }

    // MARK: - AI

    private func generate() async {
        phase = .generating
        progressLabel = "Generating your recipe…"
        errorMessage = nil
        let (cals, protein) = targetsForMode()
        let veg = profile?.isVegetarian ?? true
        let exclusions = profile?.excludedIngredients ?? ["eggs", "mushrooms"]
        if let profile { profile.aiCallsTotal += 1 }
        do {
            let result = try await vision.generateRecipe(
                prompt: keywords,
                isVegetarian: veg,
                excludedIngredients: exclusions,
                targetCalories: cals,
                targetProtein: protein
            )
            await MainActor.run { populate(from: result); phase = .review }
        } catch {
            await MainActor.run { handleError(error, stayReview: false) }
        }
    }

    private func refine() async {
        let change = refineText.trimmingCharacters(in: .whitespaces)
        guard !change.isEmpty else { return }
        phase = .generating
        progressLabel = "Updating your recipe…"
        errorMessage = nil
        let (cals, protein) = targetsForMode()
        let veg = profile?.isVegetarian ?? true
        let exclusions = profile?.excludedIngredients ?? ["eggs", "mushrooms"]
        let json = currentRecipeJSON()
        if let profile { profile.aiCallsTotal += 1 }
        do {
            let result = try await vision.generateRecipe(
                prompt: keywords,
                isVegetarian: veg,
                excludedIngredients: exclusions,
                targetCalories: cals,
                targetProtein: protein,
                previousRecipeJSON: json,
                refinement: change
            )
            await MainActor.run { populate(from: result); refineText = ""; phase = .review }
        } catch {
            await MainActor.run { handleError(error, stayReview: true) }
        }
    }

    private func handleError(_ error: Error, stayReview: Bool) {
        if let aiError = error as? AIVisionService.AIError, AIVisionService.isQuotaError(aiError) {
            errorMessage = "AI is temporarily rate-limited. Try again in a few minutes."
            if let profile { profile.aiQuotaErrorsTotal += 1; profile.aiLastErrorAt = Date() }
        } else {
            errorMessage = error.localizedDescription
        }
        // Keep the existing recipe visible on a refine failure; otherwise return to input.
        phase = (stayReview && !editIngredients.isEmpty) ? .review : .input
    }

    private func populate(from r: AIVisionService.GeneratedRecipe) {
        editName = r.name
        editServings = r.totalServings > 0 ? r.totalServings : 1
        editNotes = r.notes ?? ""
        editInstructions = r.instructions.joined(separator: "\n")
        editIngredients = r.ingredients.map {
            EditableIngredient(
                name: $0.name,
                grams: num($0.grams),
                calories: num($0.calories),
                proteinG: num($0.proteinG),
                carbsG: num($0.carbsG),
                fatG: num($0.fatG),
                fiberG: num($0.fiberG)
            )
        }
    }

    /// Serialize the current edited recipe so AI can revise it in place.
    private func currentRecipeJSON() -> String {
        let ingredientsArr: [[String: Any]] = editIngredients.map {
            [
                "name": $0.name,
                "grams": dbl($0.grams),
                "calories": dbl($0.calories),
                "protein_g": dbl($0.proteinG),
                "carbs_g": dbl($0.carbsG),
                "fat_g": dbl($0.fatG),
                "fiber_g": dbl($0.fiberG)
            ]
        }
        let dict: [String: Any] = [
            "name": editName,
            "total_servings": editServings,
            "notes": editNotes,
            "instructions": editInstructions.split(separator: "\n").map(String.init),
            "ingredients": ingredientsArr
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "{}"
    }

    // MARK: - Save

    private func save() {
        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !editIngredients.isEmpty else { return }
        let servings = editServings > 0 ? editServings : 1
        let trimmedNotes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        let recipe = Recipe(
            name: trimmedName,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            instructions: editInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
            totalServings: servings
        )
        modelContext.insert(recipe)

        for (idx, ing) in editIngredients.enumerated() {
            let grams = max(dbl(ing.grams), 1)
            // servingSizeGrams == grams and macros AT that gram amount, so
            // macros(forGrams: grams) returns them with ratio 1.
            let food = Food(
                name: ing.name,
                servingSizeGrams: grams,
                calories: dbl(ing.calories),
                proteinG: dbl(ing.proteinG),
                carbsG: dbl(ing.carbsG),
                fatG: dbl(ing.fatG),
                fiberG: dbl(ing.fiberG),
                source: .aiRecipe,
                isVegetarian: true,
                containsEggs: false,
                containsMushrooms: false
            )
            modelContext.insert(food)

            let recipeIngredient = RecipeIngredient(food: food, grams: grams, order: idx)
            recipeIngredient.recipe = recipe
            modelContext.insert(recipeIngredient)
            recipe.ingredients.append(recipeIngredient)
        }

        FoodRepository(modelContext: modelContext).saveRecipe(recipe)
        Haptics.logFood()
        dismiss()
    }

    // MARK: - Formatting

    private func num(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func formattedServings(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
