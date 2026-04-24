import SwiftUI
import SwiftData

/// Edit an existing log entry in place — grams eaten, meal type, notes.
/// Does not modify the underlying `Food` (edit its serving-size macros via re-log).
struct EditLogEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let entry: LogEntry

    @State private var amountText: String = ""
    @State private var useServings: Bool = false
    @State private var selectedMealType: MealType = .snack
    @State private var notes: String = ""

    private var gramsEaten: Double {
        let raw = Double(amountText) ?? 0
        let sz = entry.food?.servingSizeGrams ?? 0
        if useServings && sz > 0 { return raw * sz }
        return raw
    }

    private var isValid: Bool { gramsEaten > 0 }

    var body: some View {
        NavigationStack {
            Form {
                if let food = entry.food {
                    Section {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(food.name)
                                .font(.mHeadline)
                                .foregroundStyle(Color.mTextPrimary)
                            if let brand = food.brand {
                                Text(brand)
                                    .font(.mCaption)
                                    .foregroundStyle(Color.mTextSecondary)
                            }
                        }
                    }
                }

                Section("Amount") {
                    AmountPicker(
                        servingSizeGrams: entry.food.flatMap { $0.servingSizeGrams > 0 ? $0.servingSizeGrams : nil },
                        inputText: $amountText,
                        useServings: $useServings
                    )

                    if let food = entry.food, gramsEaten > 0 {
                        let macros = food.macros(forGrams: gramsEaten)
                        HStack {
                            Text("\(Int(macros.calories)) cal")
                            Spacer()
                            Text("\(Int(macros.proteinG))g protein")
                        }
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                    }
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

                Section("Notes (optional)") {
                    TextField("e.g. substitutions, extras, how it tasted", text: $notes, axis: .vertical)
                        .font(.mBody)
                        .lineLimit(2...5)
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Edit Log")
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
                    Button("Save") { save() }
                        .bold()
                        .disabled(!isValid)
                }
            }
            .onAppear { setupDefaults() }
        }
    }

    private func setupDefaults() {
        selectedMealType = entry.mealType
        notes = entry.notes ?? ""
        let sz = entry.food?.servingSizeGrams ?? 0
        if let sv = entry.servingsEaten, sv > 0, sz > 0 {
            useServings = true
            amountText = String(format: "%.2f", sv)
        } else {
            useServings = false
            amountText = "\(Int(entry.gramsEaten))"
        }
    }

    private func save() {
        let grams = gramsEaten
        guard grams > 0 else { return }
        let servings: Double? = useServings && (entry.food?.servingSizeGrams ?? 0) > 0 ? (Double(amountText) ?? nil) : nil
        let repo = FoodRepository(modelContext: modelContext)
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        repo.updateEntry(
            entry,
            grams: grams,
            mealType: selectedMealType,
            notes: trimmed.isEmpty ? nil : trimmed,
            servings: servings
        )
        Haptics.logFood()
        dismiss()
    }
}
