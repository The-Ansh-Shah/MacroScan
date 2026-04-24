import SwiftUI
import SwiftData

struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \LogEntry.loggedAt, order: .reverse)
    private var allEntries: [LogEntry]

    @Query private var profiles: [UserProfile]

    @State private var journalText: String = ""

    private var profile: UserProfile? { profiles.first }

    /// Entries from the past 7 days
    private var weekEntries: [LogEntry] {
        let startOfWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allEntries.filter { $0.loggedAt >= startOfWeek }
    }

    private var weekTotals: ScaledMacros {
        weekEntries.reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
    }

    private var daysLogged: Int {
        let dates = Set(weekEntries.map { Calendar.current.startOfDay(for: $0.loggedAt) })
        return dates.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    headerCard
                    highlightsCard
                    journalCard
                }
                .padding(.horizontal, Spacing.md)
            }
            .navigationTitle("Weekly Review")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(Color.mAccent)

            Text("Your Week in Review")
                .font(.mTitle2)
                .foregroundStyle(Color.mTextPrimary)

            Text("\(daysLogged) of 7 days logged")
                .font(.mSubheadline)
                .foregroundStyle(Color.mTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    // MARK: - Highlights

    @ViewBuilder
    private var highlightsCard: some View {
        let avgCalories = daysLogged > 0 ? weekTotals.calories / Double(daysLogged) : 0
        let avgProtein = daysLogged > 0 ? weekTotals.proteinG / Double(daysLogged) : 0
        let avgFiber = daysLogged > 0 ? weekTotals.fiberG / Double(daysLogged) : 0

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Daily Averages")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                highlightRow(label: "Calories", value: "\(Int(avgCalories))", target: profile.map { "\(Int($0.calorieTarget))" })
                highlightRow(label: "Protein", value: "\(Int(avgProtein))g", target: profile.map { "\(Int($0.proteinTargetG))g" })
                highlightRow(label: "Fiber", value: "\(Int(avgFiber))g", target: profile.map { "\(Int($0.fiberTargetG))g" })
                highlightRow(label: "Meals logged", value: "\(weekEntries.count)", target: nil)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    private func highlightRow(label: String, value: String, target: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(value)
                    .font(.mStatNumber)
                    .foregroundStyle(Color.mTextPrimary)
                if let target {
                    Text("/ \(target)")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
    }

    // MARK: - Journal

    @ViewBuilder
    private var journalCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Notes")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            TextField("How did this week go? Any thoughts...", text: $journalText, axis: .vertical)
                .font(.mBody)
                .lineLimit(4...8)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.mBgPrimary)
                )
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }
}
