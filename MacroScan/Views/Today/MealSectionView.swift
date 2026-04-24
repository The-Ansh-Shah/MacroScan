import SwiftUI

/// A section showing entries for a single meal type
struct MealSectionView: View {
    let mealType: MealType
    let entries: [LogEntry]
    let onDelete: (LogEntry) -> Void

    private var sectionMacros: ScaledMacros {
        entries.reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: mealType.icon)
                    .foregroundStyle(Color.mAccent)
                Text(mealType.displayName)
                    .font(.mHeadline)
                    .foregroundStyle(Color.mTextPrimary)

                Spacer()

                Text("\(Int(sectionMacros.calories)) cal")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextSecondary)
            }

            ForEach(entries) { entry in
                if let food = entry.food {
                    let macros = entry.scaledMacros
                    FoodRow(
                        name: food.name,
                        detail: "\(Int(entry.gramsEaten))g",
                        calories: Int(macros.calories),
                        proteinG: Int(macros.proteinG),
                        showChevron: false
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDelete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }
}
