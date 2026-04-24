import SwiftUI
import SwiftData

struct OptimizerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let menus: [DiningMenu]
    let currentTotals: ScaledMacros
    let profile: UserProfile

    @State private var plan: DiningOptimizer.OptimizedPlan?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    remainingBudgetCard
                    
                    if let plan, !plan.items.isEmpty {
                        planCard(plan)
                        acceptButton(plan)
                    } else if plan != nil {
                        EmptyStateView(
                            symbol: "xmark.circle",
                            message: "No items found that fit your\nremaining budget and preferences."
                        )
                    } else {
                        ProgressView("Optimizing...")
                            .font(.mBody)
                            .padding(Spacing.xl)
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .navigationTitle("Plan My Meal")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                plan = DiningOptimizer.optimize(
                    menus: menus,
                    currentTotals: currentTotals,
                    profile: profile
                )
            }
        }
    }

    // MARK: - Remaining Budget

    @ViewBuilder
    private var remainingBudgetCard: some View {
        let remainCal = max(0, profile.calorieTarget - currentTotals.calories)
        let remainPro = max(0, profile.proteinTargetG - currentTotals.proteinG)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Remaining Today")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            HStack(spacing: Spacing.lg) {
                VStack(spacing: Spacing.xs) {
                    Text("\(Int(remainCal))")
                        .font(.mStatNumber)
                        .foregroundStyle(Color.mTextPrimary)
                    Text("cal left")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: Spacing.xs) {
                    Text("\(Int(remainPro))g")
                        .font(.mStatNumber)
                        .foregroundStyle(Color.mTextPrimary)
                    Text("protein left")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    // MARK: - Plan Card

    @ViewBuilder
    private func planCard(_ plan: DiningOptimizer.OptimizedPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Suggested Plan")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            ForEach(plan.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(item.menuItem.name)
                            .font(.mBody)
                            .foregroundStyle(Color.mTextPrimary)
                        Text("\(item.location.displayName) · \(item.mealPeriod.capitalized)")
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("\(String(format: "%.1f", item.servings))x")
                            .font(.mHeadline)
                            .foregroundStyle(Color.mAccent)
                        Text("\(Int((item.menuItem.calories ?? 0) * item.servings)) cal")
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            Divider()

            HStack {
                Text("Total")
                    .font(.mHeadline)
                    .foregroundStyle(Color.mTextPrimary)
                Spacer()
                Text("\(Int(plan.totalCalories)) cal · \(Int(plan.totalProteinG))g protein")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextSecondary)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    // MARK: - Accept

    @ViewBuilder
    private func acceptButton(_ plan: DiningOptimizer.OptimizedPlan) -> some View {
        PrimaryButton("Accept Plan", icon: "checkmark.circle.fill") {
            acceptPlan(plan)
        }
        .padding(.horizontal, Spacing.md)
    }

    private func acceptPlan(_ plan: DiningOptimizer.OptimizedPlan) {
        let repo = FoodRepository(modelContext: modelContext)
        for item in plan.items {
            let food = Food(
                name: item.menuItem.name,
                diningLocation: item.location,
                servingSizeGrams: item.menuItem.servingGrams ?? 100,
                calories: item.menuItem.calories ?? 0,
                proteinG: item.menuItem.proteinG ?? 0,
                carbsG: item.menuItem.carbsG ?? 0,
                fatG: item.menuItem.fatG ?? 0,
                fiberG: item.menuItem.fiberG ?? 0,
                ironMg: item.menuItem.ironMg ?? 0,
                vitaminDMcg: item.menuItem.vitaminDMcg ?? 0,
                vitaminB12Mcg: item.menuItem.vitaminB12Mcg ?? 0,
                source: .diningHall
            )
            let grams = (item.menuItem.servingGrams ?? 100) * item.servings
            repo.logFood(food, grams: grams, mealType: guessMealType())
        }
        Haptics.logFood()
        dismiss()
    }

    private func guessMealType() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default: return .snack
        }
    }
}
