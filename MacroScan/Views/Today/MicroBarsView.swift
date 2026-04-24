import SwiftUI

/// Displays micro-nutrient progress bars (fiber, iron, vitamin D, B12)
struct MicroBarsView: View {
    let totals: ScaledMacros
    let profile: UserProfile

    var body: some View {
        VStack(spacing: Spacing.sm) {
            TargetBar(
                label: "Fiber",
                current: totals.fiberG,
                target: profile.fiberTargetG,
                unit: "g",
                isOverBad: false
            )
            TargetBar(
                label: "Iron",
                current: totals.ironMg,
                target: profile.ironTargetMg,
                unit: "mg",
                isOverBad: false
            )
            TargetBar(
                label: "Vitamin D",
                current: totals.vitaminDMcg,
                target: profile.vitaminDTargetMcg,
                unit: "mcg",
                isOverBad: false
            )
            TargetBar(
                label: "Vitamin B12",
                current: totals.vitaminB12Mcg,
                target: profile.vitaminB12TargetMcg,
                unit: "mcg",
                isOverBad: false
            )
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }
}
