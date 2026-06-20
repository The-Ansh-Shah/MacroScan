import SwiftUI
import SwiftData
import Charts

/// History tab — segmented into "Days" (reverse-chron day list) and "Trends" (7-day charts).
/// Tapping a day row pushes a read-only `DayView` for that date.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LogEntry.loggedAt, order: .reverse)
    private var allEntries: [LogEntry]

    @Query private var profiles: [UserProfile]

    @State private var showingWeeklyReview = false
    @State private var tab: Tab = .days

    enum Tab: String, CaseIterable, Identifiable {
        case days = "Days"
        case trends = "Trends"
        var id: String { rawValue }
    }

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(Spacing.md)

                if allEntries.isEmpty {
                    EmptyStateView(
                        symbol: "calendar",
                        message: "Your nutrition history will appear here\nafter logging a few days of meals."
                    )
                } else {
                    switch tab {
                    case .days:
                        DayListView(allEntries: allEntries, profile: profile)
                    case .trends:
                        TrendsView(allEntries: allEntries, profile: profile)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingWeeklyReview = true
                    } label: {
                        Label("Weekly Review", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            }
            .sheet(isPresented: $showingWeeklyReview) {
                WeeklyReviewView()
            }
        }
    }
}

// MARK: - Day List

private struct DayListView: View {
    let allEntries: [LogEntry]
    let profile: UserProfile?

    private var dayBuckets: [DaySummary] {
        let grouped = Dictionary(grouping: allEntries) {
            Calendar.current.startOfDay(for: $0.loggedAt)
        }
        return grouped.map { date, entries in
            let totals = entries.reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
            return DaySummary(date: date, totals: totals, entryCount: entries.count)
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            ForEach(dayBuckets) { day in
                NavigationLink {
                    PastDayView(date: day.date)
                } label: {
                    dayRow(day)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func dayRow(_ day: DaySummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(dateLabel(day.date))
                    .font(.mHeadline)
                    .foregroundStyle(Color.mTextPrimary)
                Text("\(day.entryCount) entr\(day.entryCount == 1 ? "y" : "ies")")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("\(Int(day.totals.calories)) cal")
                    .font(.mSubheadline)
                    .foregroundStyle(calorieColor(day))
                Text("\(Int(day.totals.proteinG))g protein · \(Int(day.totals.fiberG))g fiber")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
        .frame(minHeight: DesignConstants.minTapTarget)
    }

    private func calorieColor(_ day: DaySummary) -> Color {
        guard let target = profile?.calorieTarget, target > 0 else { return .mTextPrimary }
        let ratio = day.totals.calories / target
        return Color.targetColor(ratio: ratio, isOverBad: true)
    }

    private func dateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
}

/// DayView wrapped for push navigation from History.
private struct PastDayView: View {
    @State var date: Date

    var body: some View {
        DayView(date: $date, isTodayTab: false)
    }
}

// MARK: - Trends (existing 7-day charts)

private struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    let allEntries: [LogEntry]
    let profile: UserProfile?

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
        ScrollView {
            VStack(spacing: Spacing.md) {
                adherenceCard
                calorieChart
                proteinChart
                weekSummaryCard
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    @ViewBuilder
    private var adherenceCard: some View {
        let repo = FoodRepository(modelContext: modelContext)
        let stats = repo.adherence(forLastDays: 14)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Last 14 Days")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            HStack(spacing: Spacing.lg) {
                statItem(value: "\(stats.loggedDays)", total: stats.totalDays, label: "Days logged")
                statItem(value: "\(stats.hitCalorieTargetDays)", total: stats.loggedDays, label: "Hit calorie target")
                statItem(value: "\(stats.hitProteinTargetDays)", total: stats.loggedDays, label: "Hit protein target")
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    private func statItem(value: String, total: Int, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.mStatNumber)
                    .foregroundStyle(Color.mTextPrimary)
                Text("/\(total)")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
            Text(label)
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

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
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

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
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

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
        return Color.targetColor(ratio: ratio, isOverBad: isOverBad)
    }
}

// MARK: - Supporting Types

private struct DaySummary: Identifiable {
    let date: Date
    let totals: ScaledMacros
    let entryCount: Int
    var id: Date { date }
}
