import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LogEntry.loggedAt, order: .reverse)
    private var allEntries: [LogEntry]

    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    /// Last 7 days of data for charts
    private var last7Days: [DaySummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return nil }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: date)!
            let dayEntries = allEntries.filter { $0.loggedAt >= date && $0.loggedAt < nextDay }
            let totals = dayEntries.reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
            return DaySummary(date: date, totals: totals, entryCount: dayEntries.count)
        }
    }

    var body: some View {
        NavigationStack {
            if allEntries.isEmpty {
                EmptyStateView(
                    symbol: "calendar",
                    message: "Your nutrition history will appear here\nafter logging a few days of meals."
                )
            } else {
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        calorieChart
                        proteinChart
                        weekSummaryCard
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
        }
        .navigationTitle("History")
    }

    // MARK: - Calorie Chart

    @ViewBuilder
    private var calorieChart: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Calories")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            Chart(last7Days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Calories", day.totals.calories)
                )
                .foregroundStyle(barColor(current: day.totals.calories, target: profile?.calorieTarget ?? 0, isOverBad: true))
                .cornerRadius(4)

                if let target = profile?.calorieTarget {
                    RuleMark(y: .value("Target", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.mTextTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    // MARK: - Protein Chart

    @ViewBuilder
    private var proteinChart: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Protein")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            Chart(last7Days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Protein", day.totals.proteinG)
                )
                .foregroundStyle(barColor(current: day.totals.proteinG, target: profile?.proteinTargetG ?? 0, isOverBad: false))
                .cornerRadius(4)

                if let target = profile?.proteinTargetG {
                    RuleMark(y: .value("Target", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.mTextTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    // MARK: - Week Summary

    @ViewBuilder
    private var weekSummaryCard: some View {
        let activeDays = last7Days.filter { $0.entryCount > 0 }
        let avgCalories = activeDays.isEmpty ? 0 : activeDays.map(\.totals.calories).reduce(0, +) / Double(activeDays.count)
        let avgProtein = activeDays.isEmpty ? 0 : activeDays.map(\.totals.proteinG).reduce(0, +) / Double(activeDays.count)
        let totalEntries = last7Days.map(\.entryCount).reduce(0, +)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("7-Day Summary")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            HStack(spacing: Spacing.lg) {
                summaryItem(label: "Avg Cal", value: "\(Int(avgCalories))")
                summaryItem(label: "Avg Protein", value: "\(Int(avgProtein))g")
                summaryItem(label: "Days Logged", value: "\(activeDays.count)/7")
                summaryItem(label: "Total Entries", value: "\(totalEntries)")
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    private func summaryItem(label: String, value: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.mStatNumber)
                .foregroundStyle(Color.mTextPrimary)
            Text(label)
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func barColor(current: Double, target: Double, isOverBad: Bool) -> Color {
        guard target > 0 else { return Color.mUnder }
        let ratio = current / target
        if ratio >= 1.0 {
            return isOverBad ? Color.mOver : Color.mOnTarget
        } else if ratio >= 0.7 {
            return Color.mApproaching
        }
        return Color.mUnder
    }
}

// MARK: - Supporting Types

private struct DaySummary: Identifiable {
    let date: Date
    let totals: ScaledMacros
    let entryCount: Int
    var id: Date { date }
}
