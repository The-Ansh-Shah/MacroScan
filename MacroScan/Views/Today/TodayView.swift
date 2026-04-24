import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<LogEntry> { entry in
        entry.loggedAt >= Date().startOfDayValue
    }, sort: \LogEntry.loggedAt, order: .reverse)
    private var todayEntries: [LogEntry]

    @Query private var profiles: [UserProfile]

    @State private var showingAddSheet = false

    private var profile: UserProfile? { profiles.first }

    private var dailyTotals: ScaledMacros {
        todayEntries.reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if let profile {
                        macroRingsSection(profile: profile)
                    }

                    if todayEntries.isEmpty {
                        EmptyStateView(
                            symbol: "fork.knife",
                            message: "No meals logged today.\nScan, snap, or add manually.",
                            buttonTitle: "Add Food",
                            action: { showingAddSheet = true }
                        )
                        .padding(.top, Spacing.xl)
                    } else {
                        mealSections
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingAddSheet = true } label: {
                            Label("Manual Entry", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.mTitle3)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                Text("Add Food — Coming Soon")
                    .presentationDetents([.medium])
            }
        }
    }

    @ViewBuilder
    private func macroRingsSection(profile: UserProfile) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                MacroRing(
                    label: "Calories",
                    current: dailyTotals.calories,
                    target: profile.calorieTarget,
                    unit: "cal",
                    isOverBad: true
                )
                MacroRing(
                    label: "Protein",
                    current: dailyTotals.proteinG,
                    target: profile.proteinTargetG,
                    unit: "g",
                    isOverBad: false
                )
                MacroRing(
                    label: "Carbs",
                    current: dailyTotals.carbsG,
                    target: profile.carbTargetG,
                    unit: "g",
                    isOverBad: false
                )
                MacroRing(
                    label: "Fat",
                    current: dailyTotals.fatG,
                    target: profile.fatTargetG,
                    unit: "g",
                    isOverBad: true
                )
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    @ViewBuilder
    private var mealSections: some View {
        ForEach(MealType.allCases) { mealType in
            let entries = todayEntries.filter { $0.mealType == mealType }
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Image(systemName: mealType.icon)
                            .foregroundStyle(Color.mAccent)
                        Text(mealType.displayName)
                            .font(.mHeadline)
                            .foregroundStyle(Color.mTextPrimary)
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
    }
}

// Helper to make Date predicate work with SwiftData
extension Date {
    /// Start of today as a fixed value for predicates
    static var startOfDayValue: Date {
        Calendar.current.startOfDay(for: Date())
    }
}
