import SwiftUI
import SwiftData

/// Non-AI "what should I eat?" view.
/// Shows remaining targets and suggests foods from the user's personal DB
/// that best close the biggest nutritional gap.
struct CloseGapView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \LogEntry.loggedAt, order: .reverse)
    private var allEntries: [LogEntry]

    @Query(sort: \Food.timesLogged, order: .reverse)
    private var allFoods: [Food]

    @Query private var profiles: [UserProfile]

    @State private var selectedFood: Food?

    private var profile: UserProfile? { profiles.first }

    private var todayTotals: ScaledMacros {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return allEntries
            .filter { $0.loggedAt >= startOfToday }
            .reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
    }

    private var suggestions: [Food] {
        guard let profile else { return [] }
        return MealRanker.closeGapSuggestions(
            foods: allFoods,
            currentTotals: todayTotals,
            profile: profile,
            limit: 10
        )
    }

    /// Bundled vegetarian high-protein library, ranked by protein density.
    /// Always browsable so the view is useful even before the user has logged much.
    private var curatedPicks: [Food] {
        guard let profile else { return [] }
        return allFoods
            .filter { $0.source == .curated && $0.isAllowed(for: profile) }
            .sorted { ($0.proteinG / max($0.calories, 1)) > ($1.proteinG / max($1.calories, 1)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if let profile {
                        gapSummaryCard(profile: profile)
                    }

                    if suggestions.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            message: allFoods.isEmpty
                                ? "Log some foods first so we can\nmake personalized suggestions."
                                : "You're close to your targets!\nNo more suggestions needed."
                        )
                        .padding(.top, Spacing.lg)
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Suggestions")
                                .font(.mHeadline)
                                .foregroundStyle(Color.mTextPrimary)

                            ForEach(suggestions) { food in
                                Button {
                                    selectedFood = food
                                } label: {
                                    FoodRow(
                                        name: food.name,
                                        detail: food.brand ?? "\(Int(food.servingSizeGrams))g serving",
                                        calories: Int(food.calories),
                                        proteinG: Int(food.proteinG),
                                        showChevron: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                                .fill(Color.mBgSecondary)
                        )
                    }

                    if !curatedPicks.isEmpty {
                        curatedSection
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .navigationTitle("Close the Gap")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedFood) { food in
                ScanResultSheet(food: food)
            }
        }
    }

    // MARK: - Curated picks

    @ViewBuilder
    private var curatedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Vegetarian high-protein picks")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)
            Text("Lean, egg- & mushroom-free options ranked by protein per calorie.")
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)

            ForEach(curatedPicks) { food in
                Button {
                    selectedFood = food
                } label: {
                    FoodRow(
                        name: food.name,
                        detail: "\(Int(food.servingSizeGrams))g serving",
                        calories: Int(food.calories),
                        proteinG: Int(food.proteinG),
                        showChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    // MARK: - Gap Summary

    @ViewBuilder
    private func gapSummaryCard(profile: UserProfile) -> some View {
        let calGap = max(0, profile.calorieTarget - todayTotals.calories)
        let proGap = max(0, profile.proteinTargetG - todayTotals.proteinG)
        let fibGap = max(0, profile.fiberTargetG - todayTotals.fiberG)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Still Need Today")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            HStack(spacing: Spacing.md) {
                gapItem(label: "Calories", remaining: calGap, unit: "cal", atTarget: calGap <= 0)
                gapItem(label: "Protein", remaining: proGap, unit: "g", atTarget: proGap <= 0)
                gapItem(label: "Fiber", remaining: fibGap, unit: "g", atTarget: fibGap <= 0)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    private func gapItem(label: String, remaining: Double, unit: String, atTarget: Bool) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(atTarget ? "0" : "\(Int(remaining))")
                .font(.mStatNumber)
                .foregroundStyle(atTarget ? Color.mOnTarget : Color.mTextPrimary)
            Text("\(unit) \(label.lowercased())")
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
