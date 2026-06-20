import SwiftUI

struct TargetBar: View {
    let label: String
    let current: Double
    let target: Double
    let unit: String
    let isOverBad: Bool

    private var ratio: Double {
        guard target > 0 else { return 0 }
        return current / target
    }

    private var fillRatio: Double {
        min(ratio, 1.0)
    }

    private var barColor: Color {
        .targetColor(ratio: ratio, isOverBad: isOverBad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(label)
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextSecondary)
                Spacer()
                Text("\(String(format: "%.1f", current)) / \(String(format: "%.1f", target)) \(unit)")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                        .fill(Color.mUnder.opacity(0.16))
                        .frame(height: barHeight)

                    RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                        .fill(Color.macroGradient(barColor))
                        .frame(width: geometry.size.width * fillRatio, height: barHeight)
                        .animation(DesignConstants.ringAnimation, value: fillRatio)
                }
            }
            .frame(height: barHeight)
        }
    }

    private let barHeight: CGFloat = 10
}

#Preview {
    VStack(spacing: Spacing.md) {
        TargetBar(label: "Fiber", current: 12, target: 30, unit: "g", isOverBad: false)
        TargetBar(label: "Iron", current: 15, target: 18, unit: "mg", isOverBad: false)
        TargetBar(label: "Vitamin D", current: 16, target: 15, unit: "mcg", isOverBad: false)
    }
    .padding()
}
