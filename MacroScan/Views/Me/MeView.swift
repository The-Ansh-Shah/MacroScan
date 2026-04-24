import SwiftUI
import SwiftData

struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMeasurement.recordedAt, order: .reverse)
    private var measurements: [BodyMeasurement]

    @State private var showingLogMeasurement = false
    @State private var showingStalePrompt = false
    @State private var showingPreflightEditor = false
    @State private var navigateToPlanner = false

    private var profile: UserProfile? { profiles.first }
    private var latestMeasurement: BodyMeasurement? { measurements.first }

    private var measurementIsStale: Bool {
        guard let profile else { return true }
        if profile.heightIn == nil || profile.ageYears == nil || profile.biologicalSex == .unspecified {
            return true
        }
        guard let latest = latestMeasurement else { return true }
        let daysSince = Calendar.current.dateComponents([.day], from: latest.recordedAt, to: Date()).day ?? 999
        return daysSince > 7
    }

    private var stalePromptMessage: String {
        if let latest = latestMeasurement {
            let days = Calendar.current.dateComponents([.day], from: latest.recordedAt, to: Date()).day ?? 0
            return "Your most recent measurement is from \(days) days ago. Updating it gives you a more accurate plan."
        }
        return "You haven't logged any measurements yet. Adding one gives you a more accurate plan."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if let profile {
                        headerCard(profile: profile)
                        activeGoalCard(profile: profile)
                        quickActionsSection(profile: profile)
                        recentMeasurementsSection
                        targetsSummary(profile: profile)
                        microTargetsSection(profile: profile)
                    } else {
                        ProgressView()
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .navigationTitle("Me")
            .sheet(isPresented: $showingLogMeasurement) {
                if let profile {
                    LogMeasurementSheet(profile: profile)
                }
            }
            .sheet(isPresented: $showingPreflightEditor, onDismiss: {
                navigateToPlanner = true
            }) {
                if let profile {
                    LogMeasurementSheet(profile: profile)
                }
            }
            .navigationDestination(isPresented: $navigateToPlanner) {
                GoalPlannerView()
            }
            .confirmationDialog("Update measurements?", isPresented: $showingStalePrompt) {
                Button("Update measurements") {
                    showingPreflightEditor = true
                }
                Button("Use existing data") {
                    navigateToPlanner = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(stalePromptMessage)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerCard(profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Current weight")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                    if let w = latestMeasurement?.weightLb ?? profile.bodyWeightLb {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                            Text("\(String(format: "%.1f", w)) lb")
                                .font(.mTitle)
                                .foregroundStyle(Color.mTextPrimary)
                                .monospacedDigit()
                            trendArrow
                        }
                    } else {
                        Text("—")
                            .font(.mTitle)
                            .foregroundStyle(Color.mTextTertiary)
                    }
                }
                Spacer()
                bodyFatBadge(profile: profile)
            }

            if let m = latestMeasurement {
                Text("as of \(m.recordedAt, format: .dateTime.month().day())")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    @ViewBuilder
    private var trendArrow: some View {
        if measurements.count >= 2 {
            let current = measurements[0].weightLb
            let previous = measurements[1].weightLb
            let diff = current - previous
            if abs(diff) > 0.1 {
                Image(systemName: diff < 0 ? "arrow.down.right" : "arrow.up.right")
                    .font(.mCaption)
                    .foregroundStyle(diff < 0 ? Color.mOnTarget : Color.mApproaching)
            }
        }
    }

    @ViewBuilder
    private func bodyFatBadge(profile: UserProfile) -> some View {
        let estimate = BodyCompositionService.currentBodyFat(profile: profile, latest: latestMeasurement)
        if let bf = estimate {
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("Body fat")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
                Text("\(String(format: "%.1f", bf.pct))%")
                    .font(.mTitle3)
                    .foregroundStyle(Color.mTextPrimary)
                    .monospacedDigit()
                Text(bf.source.rawValue.capitalized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
    }

    // MARK: - Active Goal

    @ViewBuilder
    private func activeGoalCard(profile: UserProfile) -> some View {
        if let goal = profile.currentGoal, goal.isActive {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "target")
                        .foregroundStyle(Color.mAccent)
                    Text("Active Goal")
                        .font(.mHeadline)
                        .foregroundStyle(Color.mTextPrimary)
                    Spacer()
                    daysRemainingBadge(goal: goal)
                }

                HStack(spacing: Spacing.lg) {
                    if let tw = goal.targetWeightLb {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Target").font(.mCaption).foregroundStyle(Color.mTextTertiary)
                            Text("\(String(format: "%.1f", tw)) lb")
                                .font(.mBody).monospacedDigit()
                        }
                    }
                    if let tbf = goal.targetBodyFatPct {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Target BF").font(.mCaption).foregroundStyle(Color.mTextTertiary)
                            Text("\(String(format: "%.1f", tbf))%")
                                .font(.mBody).monospacedDigit()
                        }
                    }
                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    NavigationLink {
                        GoalProgressView()
                    } label: {
                        Label("View progress", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.mBody)
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.xs)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.mAccent)

                    NavigationLink {
                        GoalPlannerView()
                    } label: {
                        Label("Recompute", systemImage: "arrow.triangle.2.circlepath")
                            .font(.mBody)
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.xs)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.mTextSecondary)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                    .fill(Color.mBgSecondary)
            )
        }
    }

    @ViewBuilder
    private func daysRemainingBadge(goal: WeightGoal) -> some View {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0
        Text("\(max(0, days))d left")
            .font(.mCaption)
            .foregroundStyle(days > 14 ? Color.mTextSecondary : Color.mApproaching)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private func quickActionsSection(profile: UserProfile) -> some View {
        HStack(spacing: Spacing.sm) {
            quickActionButton(
                icon: "plus.circle",
                label: "Log\nmeasurement"
            ) {
                showingLogMeasurement = true
            }

            quickActionButton(
                icon: "target",
                label: "Plan\na goal"
            ) {
                if measurementIsStale {
                    showingStalePrompt = true
                } else {
                    navigateToPlanner = true
                }
            }
        }
    }

    @ViewBuilder
    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.mTitle3)
                    .foregroundStyle(Color.mAccent)
                Text(label)
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                    .fill(Color.mBgSecondary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Measurements

    @ViewBuilder
    private var recentMeasurementsSection: some View {
        let recent = Array(measurements.prefix(5))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Recent Measurements")
                        .font(.mHeadline)
                        .foregroundStyle(Color.mTextPrimary)
                    Spacer()
                    NavigationLink {
                        BodyCompositionView()
                    } label: {
                        Text("View all")
                            .font(.mCaption)
                            .foregroundStyle(Color.mAccent)
                    }
                }

                ForEach(recent) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.recordedAt, format: .dateTime.month().day())
                                .font(.mBody)
                                .foregroundStyle(Color.mTextPrimary)
                            if let bf = m.bodyFatPct {
                                Text("\(String(format: "%.1f", bf))% BF")
                                    .font(.mCaption)
                                    .foregroundStyle(Color.mTextTertiary)
                            }
                        }
                        Spacer()
                        Text("\(String(format: "%.1f", m.weightLb)) lb")
                            .font(.mBody)
                            .foregroundStyle(Color.mTextSecondary)
                            .monospacedDigit()
                    }
                    if m.id != recent.last?.id {
                        Divider()
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

    // MARK: - Targets Summary

    @ViewBuilder
    private func targetsSummary(profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Daily Targets")
                    .font(.mHeadline)
                    .foregroundStyle(Color.mTextPrimary)
                Spacer()
                if profile.currentGoal?.isActive == true {
                    Text("Goal-driven")
                        .font(.mCaption)
                        .foregroundStyle(Color.mAccent)
                } else {
                    Text("Manual")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }

            HStack(spacing: Spacing.lg) {
                targetStat("Calories", "\(Int(profile.calorieTarget))")
                targetStat("Protein", "\(Int(profile.proteinTargetG))g")
                targetStat("Steps", "\(profile.dailyStepTarget)")
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    @ViewBuilder
    private func targetStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.mBody)
                .foregroundStyle(Color.mTextPrimary)
                .monospacedDigit()
            Text(label)
                .font(.mCaption)
                .foregroundStyle(Color.mTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Micronutrient Targets

    @ViewBuilder
    private func microTargetsSection(profile: UserProfile) -> some View {
        // `profile` is a SwiftData @Model — access via a nested Bindable wrapper
        MicroTargetsEditor(profile: profile)
    }
}

private struct MicroTargetsEditor: View {
    @Bindable var profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Micronutrient Targets")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            microRow("Fiber", value: $profile.fiberTargetG, unit: "g")
            Divider()
            microRow("Iron", value: $profile.ironTargetMg, unit: "mg")
            Divider()
            microRow("Vitamin D", value: $profile.vitaminDTargetMcg, unit: "mcg")
            Divider()
            microRow("Vitamin B12", value: $profile.vitaminB12TargetMcg, unit: "mcg")
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    @ViewBuilder
    private func microRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
                .font(.mBody)
                .foregroundStyle(Color.mTextPrimary)
            Spacer()
            TextField("0", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
            Text(unit)
                .font(.mCaption)
                .foregroundStyle(Color.mTextTertiary)
                .frame(width: 28, alignment: .leading)
        }
    }
}
