import SwiftUI
import SwiftData

struct QuickAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editingEntry: LogEntry?

    @State private var name = ""
    @State private var calories = ""
    @State private var proteinG = ""
    @State private var carbsG = ""
    @State private var fatG = ""
    @State private var fiberG = ""
    @State private var selectedMealType: MealType = .lunch
    @State private var notes = ""

    private var isValid: Bool {
        guard let cal = Double(calories), cal > 0 else { return false }
        return true
    }

    private var isEditing: Bool { editingEntry != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("What did you eat?") {
                    TextField("Name (optional)", text: $name)
                        .font(.mBody)
                }

                Section("Calories") {
                    numberField("Calories", text: $calories)
                }

                Section("Macros (optional)") {
                    numberField("Protein (g)", text: $proteinG)
                    numberField("Carbs (g)", text: $carbsG)
                    numberField("Fat (g)", text: $fatG)
                    numberField("Fiber (g)", text: $fiberG)
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
                    TextField("e.g. restaurant dinner, friend's cooking", text: $notes, axis: .vertical)
                        .font(.mBody)
                        .lineLimit(2...5)
                }

                if isValid, let cal = Double(calories) {
                    Section("Preview") {
                        HStack {
                            Text("\(Int(cal)) cal")
                            Spacer()
                            if let pro = Double(proteinG), pro > 0 {
                                Text("\(Int(pro))g protein")
                            }
                        }
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(isEditing ? "Edit Quick Add" : "Quick Add")
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
                    Button(isEditing ? "Save" : "Log") {
                        save()
                    }
                    .bold()
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let entry = editingEntry {
                    name = entry.quickAddName ?? ""
                    calories = entry.quickAddCalories.map { "\(Int($0))" } ?? ""
                    proteinG = entry.quickAddProteinG.map { "\(Int($0))" } ?? ""
                    carbsG = entry.quickAddCarbsG.map { "\(Int($0))" } ?? ""
                    fatG = entry.quickAddFatG.map { "\(Int($0))" } ?? ""
                    fiberG = entry.quickAddFiberG.map { "\(Int($0))" } ?? ""
                    selectedMealType = entry.mealType
                    notes = entry.notes ?? ""
                } else {
                    guessMealType()
                }
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

    private func save() {
        guard let cal = Double(calories), cal > 0 else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let entry = editingEntry {
            let repo = FoodRepository(modelContext: modelContext)
            repo.updateQuickAddEntry(
                entry,
                name: trimmedName.isEmpty ? nil : trimmedName,
                calories: cal,
                proteinG: Double(proteinG),
                carbsG: Double(carbsG),
                fatG: Double(fatG),
                fiberG: Double(fiberG),
                mealType: selectedMealType,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
        } else {
            let repo = FoodRepository(modelContext: modelContext)
            repo.logQuickAdd(
                name: trimmedName.isEmpty ? nil : trimmedName,
                calories: cal,
                proteinG: Double(proteinG),
                carbsG: Double(carbsG),
                fatG: Double(fatG),
                fiberG: Double(fiberG),
                mealType: selectedMealType,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
        }

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
