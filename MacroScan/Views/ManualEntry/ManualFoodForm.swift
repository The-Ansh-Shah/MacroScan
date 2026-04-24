import SwiftUI
import SwiftData

struct ManualFoodForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var servingGrams = ""
    @State private var calories = ""
    @State private var proteinG = ""
    @State private var carbsG = ""
    @State private var fatG = ""
    @State private var fiberG = ""
    @State private var gramsEaten = ""
    @State private var selectedMealType: MealType = .lunch

    private var isValid: Bool {
        !name.isEmpty &&
        Double(servingGrams) != nil && (Double(servingGrams) ?? 0) > 0 &&
        Double(calories) != nil &&
        Double(proteinG) != nil &&
        Double(carbsG) != nil &&
        Double(fatG) != nil &&
        Double(gramsEaten) != nil && (Double(gramsEaten) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food Info") {
                    TextField("Name", text: $name)
                        .font(.mBody)
                    TextField("Brand (optional)", text: $brand)
                        .font(.mBody)
                }

                Section("Per Serving") {
                    numberField("Serving size (g)", text: $servingGrams)
                    numberField("Calories", text: $calories)
                    numberField("Protein (g)", text: $proteinG)
                    numberField("Carbs (g)", text: $carbsG)
                    numberField("Fat (g)", text: $fatG)
                    numberField("Fiber (g)", text: $fiberG)
                }

                Section("Log") {
                    numberField("Amount eaten (g)", text: $gramsEaten)

                    Picker("Meal", selection: $selectedMealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedMealType) { _, _ in
                        Haptics.selectionChanged()
                    }
                }

                if isValid, let grams = Double(gramsEaten), let serving = Double(servingGrams),
                   let cal = Double(calories), let pro = Double(proteinG) {
                    Section("Preview") {
                        let ratio = grams / serving
                        HStack {
                            Text("\(Int(cal * ratio)) cal")
                            Spacer()
                            Text("\(Int(pro * ratio))g protein")
                        }
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Manual Entry")
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
                        saveAndLog()
                    }
                    .bold()
                    .disabled(!isValid)
                }
            }
            .onAppear {
                guessMealType()
            }
        }
    }

    @ViewBuilder
    private func numberField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.mBody)
            Spacer()
            TextField("0", text: text)
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func saveAndLog() {
        guard isValid,
              let serving = Double(servingGrams),
              let cal = Double(calories),
              let pro = Double(proteinG),
              let carb = Double(carbsG),
              let fat = Double(fatG),
              let grams = Double(gramsEaten) else { return }

        let food = Food(
            name: name,
            brand: brand.isEmpty ? nil : brand,
            servingSizeGrams: serving,
            calories: cal,
            proteinG: pro,
            carbsG: carb,
            fatG: fat,
            fiberG: Double(fiberG) ?? 0,
            source: .manual
        )

        let repo = FoodRepository(modelContext: modelContext)
        repo.save(food: food)
        repo.logFood(food, grams: grams, mealType: selectedMealType)
        Haptics.logFood()
        dismiss()
    }

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

#Preview {
    ManualFoodForm()
        .modelContainer(for: [Food.self, LogEntry.self, UserProfile.self, BodyMeasurement.self, WeightGoal.self], inMemory: true)
}
