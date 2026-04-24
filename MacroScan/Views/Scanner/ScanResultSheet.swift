import SwiftUI
import SwiftData

struct ScanResultSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let food: Food
    @State private var gramsEaten: String = ""
    @State private var selectedMealType: MealType = .lunch

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Serving") {
                    HStack {
                        Text("Standard serving")
                            .font(.mBody)
                        Spacer()
                        Text("\(Int(food.servingSizeGrams))g")
                            .font(.mBody)
                            .foregroundStyle(Color.mTextSecondary)
                    }

                    HStack {
                        Text("Amount eaten")
                            .font(.mBody)
                        Spacer()
                        TextField("grams", text: $gramsEaten)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundStyle(Color.mTextSecondary)
                    }
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

                if let grams = Double(gramsEaten), grams > 0 {
                    Section("Nutrition") {
                        let macros = food.macros(forGrams: grams)
                        nutritionRow("Calories", value: macros.calories, unit: "cal")
                        nutritionRow("Protein", value: macros.proteinG, unit: "g")
                        nutritionRow("Carbs", value: macros.carbsG, unit: "g")
                        nutritionRow("Fat", value: macros.fatG, unit: "g")
                        nutritionRow("Fiber", value: macros.fiberG, unit: "g")
                    }
                }

                // Warnings
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
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(Double(gramsEaten) == nil || (Double(gramsEaten) ?? 0) <= 0)
                }
            }
            .onAppear {
                gramsEaten = "\(Int(food.servingSizeGrams))"
                guessMealType()
            }
        }
    }

    private func nutritionRow(_ label: String, value: Double, unit: String) -> some View {
        HStack {
            Text(label)
                .font(.mBody)
            Spacer()
            Text("\(String(format: "%.1f", value)) \(unit)")
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
        }
    }

    private func logEntry() {
        guard let grams = Double(gramsEaten), grams > 0 else { return }
        let repo = FoodRepository(modelContext: modelContext)
        repo.logFood(food, grams: grams, mealType: selectedMealType)
        Haptics.logFood()
        dismiss()
    }

    /// Guess meal type based on time of day
    private func guessMealType() {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: selectedMealType = .breakfast
        case 11..<15: selectedMealType = .lunch
        case 15..<21: selectedMealType = .dinner
        default: selectedMealType = .snack
        }
    }
}

extension Food: Identifiable {}
