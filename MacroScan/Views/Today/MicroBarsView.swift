import SwiftUI

/// Displays the fiber progress bar vs the profile's fiber target.
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
        }
        .padding(Spacing.md)
        .mCard()
    }
}
