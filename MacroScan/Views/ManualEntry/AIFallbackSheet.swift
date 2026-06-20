#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

/// Fallback presented when AI vision analysis fails terminally.
/// Shows the captured photo (so the user can see what they snapped) and an inline
/// manual form. The photo is preserved into the LogEntry on save.
struct AIFallbackSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let quotaError: Bool

    @State private var name = ""
    @State private var servingGrams = ""
    @State private var calories = ""
    @State private var proteinG = ""
    @State private var carbsG = ""
    @State private var fatG = ""
    @State private var fiberG = ""
    @State private var gramsEaten = ""
    @State private var selectedMealType: MealType = .lunch
    @State private var notes: String = ""

    private var isValid: Bool {
        !name.isEmpty &&
        (Double(servingGrams) ?? 0) > 0 &&
        Double(calories) != nil &&
        Double(proteinG) != nil &&
        Double(carbsG) != nil &&
        Double(fatG) != nil &&
        (Double(gramsEaten) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if quotaError {
                    Section {
                        Label(
                            "AI analysis is temporarily rate-limited. This usually resolves within a few minutes.",
                            systemImage: "hourglass"
                        )
                        .font(.mSubheadline)
                        .foregroundStyle(Color.mApproaching)
                    }
                } else {
                    Section {
                        Label(
                            "AI analysis isn't available right now. You can still log this manually.",
                            systemImage: "info.circle"
                        )
                        .font(.mSubheadline)
                        .foregroundStyle(Color.mTextSecondary)
                    }
                }

                Section("Photo") {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Food Info") {
                    TextField("Name", text: $name)
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
                }

                Section("Notes (optional)") {
                    TextField("Any context", text: $notes, axis: .vertical)
                        .font(.mBody)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("Manual Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.sheetDismissed()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { saveAndLog() }
                        .bold()
                        .disabled(!isValid)
                }
            }
            .onAppear { selectedMealType = .currentGuess }
        }
    }

    @ViewBuilder
    private func numberField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.mBody)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
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
            servingSizeGrams: serving,
            calories: cal,
            proteinG: pro,
            carbsG: carb,
            fatG: fat,
            fiberG: Double(fiberG) ?? 0,
            source: .manual
        )

        let photoData = ImageResizing.resizeForUpload(image, maxDimension: 512, jpegQuality: 0.6)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let repo = FoodRepository(modelContext: modelContext)
        repo.save(food: food)
        repo.logFood(
            food,
            grams: grams,
            mealType: selectedMealType,
            photoData: photoData,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        Haptics.logFood()
        dismiss()
    }
}
#endif
