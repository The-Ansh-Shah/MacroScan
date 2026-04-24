import SwiftUI
import SwiftData

/// Top of TodayView — shows top-5 most-logged foods for quick re-logging
struct QuickLogBar: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Food.timesLogged, order: .reverse)
    private var allFoods: [Food]

    @State private var selectedFood: Food?

    private var topFoods: [Food] {
        MealRanker.rank(foods: allFoods, limit: 5)
    }

    var body: some View {
        if !topFoods.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Quick Log")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(topFoods) { food in
                            Button {
                                selectedFood = food
                            } label: {
                                VStack(spacing: Spacing.xs) {
                                    Text(food.name)
                                        .font(.mCaption)
                                        .foregroundStyle(Color.mTextPrimary)
                                        .lineLimit(1)
                                    Text("\(Int(food.calories)) cal")
                                        .font(.mCaption)
                                        .foregroundStyle(Color.mTextTertiary)
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.mBgSecondary)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .sheet(item: $selectedFood) { food in
                ScanResultSheet(food: food)
            }
        }
    }
}
