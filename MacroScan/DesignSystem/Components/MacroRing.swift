import SwiftUI

struct MacroRing: View {
    let label: String
    let current: Double
    let target: Double
    let unit: String
    let isOverBad: Bool

    private var ratio: Double {
        guard target > 0 else { return 0 }
        return min(current / target, 1.5)
    }

    private var displayRatio: Double {
        min(ratio, 1.0)
    }

    private var ringColor: Color {
        .targetColor(ratio: ratio, isOverBad: isOverBad)
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.2), lineWidth: DesignConstants.ringStrokeWidth)

                Circle()
                    .trim(from: 0, to: displayRatio)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(
                            lineWidth: DesignConstants.ringStrokeWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(DesignConstants.ringAnimation, value: displayRatio)

                VStack(spacing: 0) {
                    Text("\(Int(current))")
                        .font(.mStatNumber)
                        .foregroundStyle(Color.mTextPrimary)
                    Text(unit)
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }

            Text(label)
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
        }
    }
}

#Preview {
    HStack(spacing: Spacing.lg) {
        MacroRing(label: "Calories", current: 1200, target: 1800, unit: "cal", isOverBad: true)
            .frame(width: 80)
        MacroRing(label: "Protein", current: 140, target: 160, unit: "g", isOverBad: false)
            .frame(width: 80)
        MacroRing(label: "Carbs", current: 100, target: 180, unit: "g", isOverBad: false)
            .frame(width: 80)
        MacroRing(label: "Fat", current: 60, target: 55, unit: "g", isOverBad: true)
            .frame(width: 80)
    }
    .padding()
}
