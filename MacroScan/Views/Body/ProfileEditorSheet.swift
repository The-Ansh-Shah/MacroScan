import SwiftUI
import SwiftData

struct ProfileEditorSheet: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    @State private var heightText: String = ""
    @State private var ageText: String = ""
    @State private var sex: BiologicalSex = .unspecified
    @State private var activity: ActivityLevel = .sedentary

    var body: some View {
        Form {
            Section("Body") {
                numberField("Height (in)", text: $heightText)
                numberField("Age", text: $ageText)
                Picker("Biological sex", selection: $sex) {
                    ForEach(BiologicalSex.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .font(.mBody)
                Picker("Activity level", selection: $activity) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .font(.mBody)
            }
        }
        .navigationTitle("Edit Profile")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .bold()
            }
        }
        .onAppear { loadFromProfile() }
    }

    @ViewBuilder
    private func numberField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.mBody)
            Spacer()
            TextField("0", text: text)
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func loadFromProfile() {
        if let h = profile.heightIn { heightText = String(h) }
        if let a = profile.ageYears { ageText = String(a) }
        sex = profile.biologicalSex
        activity = profile.activityLevel
    }

    private func save() {
        if let h = Double(heightText), h > 0 { profile.heightIn = h }
        if let a = Int(ageText), a > 0 { profile.ageYears = a }
        profile.biologicalSex = sex
        profile.activityLevel = activity
        Haptics.logFood()
        dismiss()
    }
}
