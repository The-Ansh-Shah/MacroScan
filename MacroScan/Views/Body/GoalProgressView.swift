import SwiftUI
import SwiftData
import Charts

/// Visualizes progress against the active WeightGoal. Charts actual measurements vs.
/// the linear projection from start → target across the goal window.
/// Intentionally non-judgmental — no "you're behind" language.
struct GoalProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMeasurement.recordedAt) private var measurements: [BodyMeasurement]

    private var profile: UserProfile? { profiles.first }
    private var goal: WeightGoal? { profile?.currentGoal }

    private var trend: [(date: Date, lb: Double)] {
        BodyCompositionService.trendWeights(from: measurements)
    }

    private var projection: BodyCompositionService.GoalProjection? {
        guard let goal, goal.targetWeightLb != nil else { return nil }
        let repo = FoodRepository(modelContext: modelContext)
        let empirical = BodyCompositionService.empiricalTDEE(
            intakeByDay: repo.trailingDailyIntake(days: 28),
            trendWeights: trend
        )
        return BodyCompositionService.projectGoal(goal: goal, trendWeights: trend, empiricalTDEE: empirical)
    }

    var body: some View {
        Group {
            if let goal, let target = goal.targetWeightLb {
                content(goal: goal, target: target)
            } else {
                EmptyStateView(
                    symbol: "target",
                    message: "No active goal. Set one in Goal Planner to see progress here."
                )
            }
        }
        .navigationTitle("Goal Progress")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func content(goal: WeightGoal, target: Double) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                summaryCard(goal: goal, target: target)

                if let projection {
                    statusCard(projection)
                }

                chartCard(goal: goal, target: target)

                Text(GoalPlanning.disclaimer)
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
            .padding(Spacing.md)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private func statusCard(_ p: BodyCompositionService.GoalProjection) -> some View {
        let style = statusStyle(p.status)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: style.icon)
                    .foregroundStyle(style.color)
                Text(style.label)
                    .font(.mHeadline)
                    .foregroundStyle(style.color)
            }
            Text(detailText(p))
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    private func statusStyle(_ s: BodyCompositionService.GoalProjection.Status) -> (label: String, color: Color, icon: String) {
        switch s {
        case .onTrack:        return ("On track", .mOnTarget, "checkmark.circle.fill")
        case .ahead:          return ("Ahead of schedule", .mOnTarget, "arrow.up.forward.circle.fill")
        case .behind:         return ("Behind schedule", .mApproaching, "exclamationmark.triangle.fill")
        case .wrongDirection: return ("Stalled", .mApproaching, "pause.circle.fill")
        case .noData:         return ("Not enough data yet", .mTextTertiary, "hourglass")
        }
    }

    private func detailText(_ p: BodyCompositionService.GoalProjection) -> String {
        guard p.status != .noData else {
            return "Log your weight a few more times to see a progress forecast."
        }
        var parts: [String] = []
        let rate = abs(p.observedRateLbPerWeek)
        if rate < 0.05 {
            parts.append(String(format: "Trend weight is holding around %.1f lb.", p.currentTrendLb))
        } else {
            let dir = p.observedRateLbPerWeek < 0 ? "losing" : "gaining"
            parts.append(String(format: "Currently %@ %.2f lb/week (trend %.1f lb).", dir, rate, p.currentTrendLb))
        }
        if let eta = p.etaDate {
            parts.append("At this rate you'll reach your target around \(eta.formatted(.dateTime.month().day())).")
        }
        if let cals = p.correctedDailyCalories, p.status != .onTrack {
            parts.append("Aim for ~\(Int(cals.rounded())) kcal/day to hit your target date.")
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func summaryCard(goal: WeightGoal, target: Double) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Active goal")
                    .font(.mHeadline)
                    .foregroundStyle(Color.mTextPrimary)
                Spacer()
                Text(goal.targetDate, format: .dateTime.month().day())
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Start").font(.mCaption).foregroundStyle(Color.mTextTertiary)
                    Text("\(String(format: "%.1f", goal.startingWeightLb)) lb")
                        .font(.mTitle3)
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.mTextTertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("Target").font(.mCaption).foregroundStyle(Color.mTextTertiary)
                    Text("\(String(format: "%.1f", target)) lb")
                        .font(.mTitle3)
                        .foregroundStyle(Color.mAccent)
                        .monospacedDigit()
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    @ViewBuilder
    private func chartCard(goal: WeightGoal, target: Double) -> some View {
        let relevant = measurements.filter { $0.recordedAt >= goal.startedAt }
        let trendInGoal = trend.filter { $0.date >= goal.startedAt }
        let projectionLine = linearProjection(goal: goal, target: target)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Trend weight vs. projection")
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)

            Chart {
                ForEach(projectionLine, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Projected", point.weight),
                        series: .value("Series", "Projection")
                    )
                    .foregroundStyle(Color.mTextTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }

                ForEach(trendInGoal, id: \.date) { pt in
                    LineMark(
                        x: .value("Date", pt.date),
                        y: .value("Weight", pt.lb),
                        series: .value("Series", "Trend")
                    )
                    .foregroundStyle(Color.mAccent)
                    .interpolationMethod(.catmullRom)
                }

                ForEach(relevant) { m in
                    PointMark(
                        x: .value("Date", m.recordedAt),
                        y: .value("Weight", m.weightLb)
                    )
                    .foregroundStyle(Color.mAccent.opacity(0.3))
                }
            }
            .frame(height: 220)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    private struct ProjectionPoint {
        let date: Date
        let weight: Double
    }

    private func linearProjection(goal: WeightGoal, target: Double) -> [ProjectionPoint] {
        let start = goal.startedAt
        let end = goal.targetDate
        let totalSeconds = end.timeIntervalSince(start)
        guard totalSeconds > 0 else {
            return [ProjectionPoint(date: start, weight: goal.startingWeightLb)]
        }
        let startWeight = goal.startingWeightLb
        // Sample weekly
        var points: [ProjectionPoint] = []
        var cursor = start
        while cursor <= end {
            let t = cursor.timeIntervalSince(start) / totalSeconds
            let w = startWeight + (target - startWeight) * t
            points.append(ProjectionPoint(date: cursor, weight: w))
            guard let next = Calendar.current.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        // Ensure the final point lands exactly on the target date.
        if points.last?.date != end {
            points.append(ProjectionPoint(date: end, weight: target))
        }
        return points
    }
}
