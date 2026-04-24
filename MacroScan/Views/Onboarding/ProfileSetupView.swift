import SwiftUI
import SwiftData

/// First-launch onboarding. Collects body composition profile so BodyCompositionService
/// can compute BMR/TDEE. Fully skippable — missing fields just leave the personalized
/// plan unavailable until the user fills them in via Settings → Body Composition.
struct ProfileSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var profile: UserProfile

    @State private var heightInText: String = ""
    @State private var ageText: String = ""
    @State private var weightText: String = ""
    @State private var bodyFatText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set up your profile to unlock personalized calorie + protein targets. You can skip and fill this in later.")
                        .font(.mSubheadline)
                        .foregroundStyle(Color.mTextSecondary)
                }

                Section("Basics") {
                    numberField("Height (in)", text: $heightInText)
                    numberField("Age", text: $ageText)

                    Picker("Biological sex", selection: Binding(
                        get: { profile.biologicalSex },
                        set: { profile.biologicalSex = $0 }
                    )) {
                        ForEach(BiologicalSex.allCases) { sex in
                            Text(sex.displayName).tag(sex)
                        }
                    }
                }

                Section("Activity") {
                    Picker("Activity level", selection: Binding(
                        get: { profile.activityLevel },
                        set: { profile.activityLevel = $0 }
                    )) {
                        ForEach(ActivityLevel.allCases) { level in
                            VStack(alignment: .leading) {
                                Text(level.displayName)
                                Text(level.detail)
                                    .font(.mCaption)
                                    .foregroundStyle(Color.mTextSecondary)
                            }
                            .tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Body") {
                    numberField("Current weight (lb)", text: $weightText)
                    numberField("Body fat % (optional)", text: $bodyFatText)
                }

                Section {
                    Text("This is an estimate for personal tracking. Consult a physician or registered dietitian before significant dietary changes, especially if you have underlying health conditions.")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Welcome")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        Haptics.sheetDismissed()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private var canSave: Bool {
        // Allow saving with partial data — anything filled is better than nothing.
        Double(heightInText) != nil ||
        Int(ageText) != nil ||
        Double(weightText) != nil
    }

    private func loadExisting() {
        if let h = profile.heightIn { heightInText = String(h) }
        if let a = profile.ageYears { ageText = String(a) }
        if let w = profile.bodyWeightLb { weightText = String(w) }
    }

    private func save() {
        if let h = Double(heightInText), h > 0 { profile.heightIn = h }
        if let a = Int(ageText), a > 0 { profile.ageYears = a }
        if let w = Double(weightText), w > 0 {
            profile.bodyWeightLb = w
            let measurement = BodyMeasurement(
                weightLb: w,
                bodyFatPct: Double(bodyFatText)
            )
            modelContext.insert(measurement)
        }
        Haptics.logFood()
        dismiss()
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
}
