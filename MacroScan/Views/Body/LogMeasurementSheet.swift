import SwiftUI
import SwiftData

struct LogMeasurementSheet: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var weightText: String = ""
    @State private var waistText: String = ""
    @State private var neckText: String = ""
    @State private var hipText: String = ""
    @State private var bodyFatText: String = ""
    @State private var measurementNotes: String = ""
    @State private var useNavyEstimate: Bool = true

    private var sex: BiologicalSex { profile.biologicalSex }

    private var navyEstimate: Double? {
        guard let waist = Double(waistText), waist > 0,
              let neck = Double(neckText), neck > 0,
              let height = profile.heightIn, height > 0,
              sex != .unspecified else { return nil }
        let hip = Double(hipText)
        let estimate = try? BodyCompositionService.estimateBodyFatNavy(
            sex: sex,
            heightIn: height,
            waistIn: waist,
            neckIn: neck,
            hipIn: hip
        )
        return estimate?.pct
    }

    private var canSave: Bool { (Double(weightText) ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    numberField("Weight (lb)", text: $weightText)
                }

                Section("Circumferences") {
                    numberField("Waist (in)", text: $waistText)
                    numberField("Neck (in)", text: $neckText)
                    if sex == .female {
                        numberField("Hip (in)", text: $hipText)
                    }

                    if let estimate = navyEstimate, useNavyEstimate {
                        HStack {
                            Image(systemName: "function")
                                .foregroundStyle(Color.mAccent)
                            Text("Navy estimate: \(String(format: "%.1f", estimate))%")
                                .font(.mBody)
                                .foregroundStyle(Color.mOnTarget)
                        }
                    }

                    HStack {
                        Text("Body fat %").font(.mBody)
                        Spacer()
                        if useNavyEstimate && navyEstimate != nil {
                            Text("auto")
                                .font(.mCaption)
                                .foregroundStyle(Color.mTextTertiary)
                        } else {
                            TextField("optional", text: $bodyFatText)
                                #if canImport(UIKit)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }

                    if navyEstimate != nil {
                        Toggle("Use Navy estimate", isOn: $useNavyEstimate)
                            .font(.mBody)
                    }
                }

                Section("Notes (optional)") {
                    TextField("e.g. morning, fasted", text: $measurementNotes, axis: .vertical)
                        .font(.mBody)
                        .lineLimit(1...3)
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Log Measurement")
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
                        .disabled(!canSave)
                }
            }
        }
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

    private func save() {
        let weight = Double(weightText) ?? 0
        guard weight > 0 else { return }

        let waist = Double(waistText)
        let neck = Double(neckText)
        let hip = Double(hipText)

        var bf: Double? = nil
        var bfSource: BodyFatSource? = nil

        if let manual = Double(bodyFatText), manual > 0, !useNavyEstimate {
            bf = manual
            bfSource = .manual
        } else if let estimate = navyEstimate, useNavyEstimate {
            bf = estimate
            bfSource = .navy
        } else if let manual = Double(bodyFatText), manual > 0 {
            bf = manual
            bfSource = .manual
        }

        let m = BodyMeasurement(
            weightLb: weight,
            bodyFatPct: bf,
            waistIn: waist,
            neckIn: neck,
            hipIn: hip,
            bodyFatSource: bfSource,
            notes: measurementNotes.isEmpty ? nil : measurementNotes
        )
        modelContext.insert(m)

        Task {
            try? await HealthKitService.shared.writeBodyMeasurement(m)
        }

        Haptics.logFood()
        dismiss()
    }
}
