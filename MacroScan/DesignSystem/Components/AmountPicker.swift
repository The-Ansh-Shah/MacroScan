import SwiftUI

/// Segmented Servings / Grams control used in all food-log sheets.
/// Keeps grams and servings in sync; exposes the canonical `gramsEaten` + `servingsEaten` pair.
struct AmountPicker: View {
    let servingSizeGrams: Double?

    /// The input text shown to the user. Drives the displayed field.
    @Binding var inputText: String
    @Binding var useServings: Bool

    var gramsEaten: Double {
        let raw = Double(inputText) ?? 0
        if useServings, let sz = servingSizeGrams, sz > 0 {
            return raw * sz
        }
        return raw
    }

    var servingsEaten: Double? {
        guard let sz = servingSizeGrams, sz > 0 else { return nil }
        let grams = gramsEaten
        return grams > 0 ? grams / sz : nil
    }

    private var hasServingSize: Bool {
        (servingSizeGrams ?? 0) > 0
    }

    private var convertedLabel: String {
        guard let sz = servingSizeGrams, sz > 0 else { return "" }
        let raw = Double(inputText) ?? 0
        if useServings {
            let g = raw * sz
            return "= \(String(format: "%.0f", g)) g"
        } else {
            let sv = raw / sz
            return "= \(String(format: "%.2f", sv)) servings"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if hasServingSize {
                Picker("Unit", selection: $useServings) {
                    Text("Servings").tag(true)
                    Text("Grams").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: useServings) { _, _ in
                    // Convert current value to the new unit
                    guard let sz = servingSizeGrams, sz > 0,
                          let raw = Double(inputText), raw > 0 else { return }
                    if useServings {
                        // switched to servings — convert from grams
                        inputText = String(format: "%.2f", raw / sz)
                    } else {
                        // switched to grams — convert from servings
                        inputText = String(format: "%.0f", raw * sz)
                    }
                }
            }

            HStack {
                Text(useServings && hasServingSize ? "Servings" : "Grams")
                    .font(.mBody)
                    .foregroundStyle(Color.mTextPrimary)
                Spacer()
                TextField(useServings ? "1" : "100", text: $inputText)
                    #if canImport(UIKit)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                if !useServings || !hasServingSize {
                    Text("g")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }

            if hasServingSize && !convertedLabel.isEmpty {
                Text(convertedLabel)
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            } else if !hasServingSize {
                Text("No serving size data — grams only")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
    }
}
