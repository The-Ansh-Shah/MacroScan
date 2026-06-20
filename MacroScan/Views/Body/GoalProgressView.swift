import SwiftUI
import SwiftData
import Charts

/// Visualizes progress against the active WeightGoal. Charts actual measurements vs.
/// the linear projection from start → target across the goal window.
/// Intentionally non-judgmental — no "you're behind" language.
struct GoalProgressView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMeasurement.recordedAt) private var measurements: [BodyMeasurement]

    private var profile: UserProfile? { profiles.first }
    private var goal: WeightGoal? { profile?.currentGoal }

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

                chartCard(goal: goal, target: target)

                Text(GoalPlanning.disclaimer)
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
            .padding(Spacing.md)
        }
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
        let projection = linearProjection(goal: goal, target: target)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Weight vs. projection")
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)

            Chart {
                ForEach(projection, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Projected", point.weight),
                        series: .value("Series", "Projection")
                    )
                    .foregroundStyle(Color.mTextTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }

                ForEach(relevant) { m in
                    LineMark(
                        x: .value("Date", m.recordedAt),
                        y: .value("Weight", m.weightLb),
                        series: .value("Series", "Actual")
                    )
                    .foregroundStyle(Color.mAccent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", m.recordedAt),
                        y: .value("Weight", m.weightLb)
                    )
                    .foregroundStyle(Color.mAccent)
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
