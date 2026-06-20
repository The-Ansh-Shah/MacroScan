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
                    .stroke(Color.mUnder.opacity(0.18), lineWidth: ringStroke)

                Circle()
                    .trim(from: 0, to: displayRatio)
                    .stroke(
                        Color.macroGradient(ringColor),
                        style: StrokeStyle(
                            lineWidth: ringStroke,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(DesignConstants.ringAnimation, value: displayRatio)

                VStack(spacing: 1) {
                    Text("\(Int(current))")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(current > target && isOverBad ? Color.mOver : Color.mTextPrimary)
                    Text("/ \(Int(target))")
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.mTextSecondary)
                    Text(unit)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color.mTextTertiary)
                }
            }

            Text(label)
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
        }
    }

    private let ringStroke: CGFloat = 14
}

#Preview {
    VStack(spacing: Spacing.lg) {
        HStack(spacing: Spacing.md) {
            MacroRing(label: "Calories", current: 1768, target: 2000, unit: "cal", isOverBad: true)
                .frame(width: 80)
            MacroRing(label: "Protein", current: 152, target: 160, unit: "g", isOverBad: false)
                .frame(width: 80)
            MacroRing(label: "Carbs", current: 100, target: 180, unit: "g", isOverBad: false)
                .frame(width: 80)
            MacroRing(label: "Fat", current: 60, target: 55, unit: "g", isOverBad: true)
                .frame(width: 80)
        }
        HStack(spacing: Spacing.md) {
            MacroRing(label: "Calories", current: 0, target: 2000, unit: "cal", isOverBad: true)
                .frame(width: 80)
            MacroRing(label: "Protein", current: 0, target: 160, unit: "g", isOverBad: false)
                .frame(width: 80)
            MacroRing(label: "Carbs", current: 0, target: 180, unit: "g", isOverBad: false)
                .frame(width: 80)
            MacroRing(label: "Fat", current: 0, target: 55, unit: "g", isOverBad: true)
                .frame(width: 80)
        }
    }
    .padding()
}
