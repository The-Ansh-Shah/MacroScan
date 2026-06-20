import SwiftUI
import SwiftData
import Charts

/// Lists body measurements, plots weight + body fat over time, and lets the user log new ones.
/// Also prominently surfaces the computed TDEE + active goal so the user can *see* the data
/// they've entered feeding real outputs.
struct BodyCompositionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMeasurement.recordedAt, order: .reverse)
    private var measurements: [BodyMeasurement]
    @Query private var profiles: [UserProfile]

    @State private var showingLogSheet = false
    @State private var healthWeightImport: (lb: Double, recordedAt: Date)?
    @State private var healthBFImport: (pct: Double, recordedAt: Date)?
    @State private var dynamicTDEE: BodyCompositionService.TDEEResult?

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        List {
            if let profile {
                Section {
                    SummaryCard(
                        profile: profile,
                        latestMeasurement: measurements.first,
                        dynamicTDEE: dynamicTDEE
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if let hw = healthWeightImport {
                Section {
                    healthImportBanner(
                        label: "New weight from Health",
                        value: "\(String(format: "%.1f", hw.lb)) lb",
                        date: hw.recordedAt
                    ) {
                        importHealthWeight(hw)
                    }
                }
            }

            if let hb = healthBFImport {
                Section {
                    healthImportBanner(
                        label: "New body fat from Health",
                        value: "\(String(format: "%.1f", hb.pct))%",
                        date: hb.recordedAt
                    ) {
                        importHealthBodyFat(hb)
                    }
                }
            }

            if measurements.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "figure.stand",
                        message: "Log your first measurement to start tracking body composition over time.",
                        buttonTitle: "Log Measurement",
                        action: { showingLogSheet = true }
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Trends") {
                    weightChart
                    if measurements.contains(where: { $0.bodyFatPct != nil }) {
                        bodyFatChart
                    }
                }

                Section("History") {
                    ForEach(measurements) { measurement in
                        measurementRow(measurement)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            modelContext.delete(measurements[idx])
                        }
                        Haptics.deleted()
                    }
                }
            }
        }
        .navigationTitle("Body Composition")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLogSheet = true
                } label: {
                    Label("Log", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingLogSheet) {
            if let profile {
                LogMeasurementSheet(profile: profile)
            }
        }
        .task { await checkHealthKitData() }
    }

    @ViewBuilder
    private func healthImportBanner(label: String, value: String, date: Date, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(label)
                        .font(.mSubheadline)
                        .foregroundStyle(Color.mTextPrimary)
                    Text("\(value) on \(date, format: .dateTime.month().day())")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }
            Button("Import") {
                action()
            }
            .font(.mBody)
            .fontWeight(.medium)
            .buttonStyle(.bordered)
            .tint(Color.mAccent)
        }
    }

    private func checkHealthKitData() async {
        let service = HealthKitService.shared
        guard await service.isAvailable else { return }

        if let profile, !measurements.isEmpty {
            let currentWeight = FoodRepository(modelContext: modelContext).currentWeightLb(profile: profile)
            let activeEnergy = try? await service.activeEnergyBurned(forDate: Date())
            let basalEnergy = try? await service.basalEnergyBurned(forDate: Date())
            dynamicTDEE = BodyCompositionService.todaysTDEE(
                profile: profile,
                currentWeightLb: currentWeight,
                activeEnergy: activeEnergy,
                basalEnergy: basalEnergy
            )
        }

        if let hw = try? await service.latestWeightLb() {
            let latestLocal = measurements.first?.recordedAt ?? .distantPast
            if hw.recordedAt > latestLocal {
                healthWeightImport = hw
            }
        }
        if let hb = try? await service.latestBodyFatPct() {
            let latestLocalBF = measurements.first(where: { $0.bodyFatPct != nil })?.recordedAt ?? .distantPast
            if hb.recordedAt > latestLocalBF {
                healthBFImport = hb
            }
        }
    }

    private func importHealthWeight(_ hw: (lb: Double, recordedAt: Date)) {
        let m = BodyMeasurement(
            recordedAt: hw.recordedAt,
            weightLb: hw.lb,
            source: "healthkit"
        )
        modelContext.insert(m)
        healthWeightImport = nil
        Haptics.logFood()
    }

    private func importHealthBodyFat(_ hb: (pct: Double, recordedAt: Date)) {
        if let latest = measurements.first,
           Calendar.current.isDate(latest.recordedAt, inSameDayAs: hb.recordedAt) {
            latest.bodyFatPct = hb.pct
        } else {
            let m = BodyMeasurement(
                recordedAt: hb.recordedAt,
                weightLb: measurements.first?.weightLb ?? 0,
                bodyFatPct: hb.pct,
                source: "healthkit"
            )
            modelContext.insert(m)
        }
        healthBFImport = nil
        Haptics.logFood()
    }

    @ViewBuilder
    private var weightChart: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Weight (lb)")
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
            Chart(measurements) { m in
                LineMark(
                    x: .value("Date", m.recordedAt),
                    y: .value("Weight", m.weightLb)
                )
                .foregroundStyle(Color.mAccent)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", m.recordedAt),
                    y: .value("Weight", m.weightLb)
                )
                .foregroundStyle(Color.mAccent)
            }
            .frame(height: 160)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var bodyFatChart: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Body fat (%)")
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
            Chart(measurements.filter { $0.bodyFatPct != nil }) { m in
                LineMark(
                    x: .value("Date", m.recordedAt),
                    y: .value("BF%", m.bodyFatPct ?? 0)
                )
                .foregroundStyle(Color.mApproaching)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", m.recordedAt),
                    y: .value("BF%", m.bodyFatPct ?? 0)
                )
                .foregroundStyle(Color.mApproaching)
            }
            .frame(height: 160)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private func measurementRow(_ m: BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(m.recordedAt, format: .dateTime.month().day().year())
                    .font(.mBody)
                    .foregroundStyle(Color.mTextPrimary)
                Spacer()
                Text("\(String(format: "%.1f", m.weightLb)) lb")
                    .font(.mBody)
                    .foregroundStyle(Color.mTextSecondary)
                    .monospacedDigit()
            }
            HStack(spacing: Spacing.md) {
                if let bf = m.bodyFatPct {
                    Label("\(String(format: "%.1f", bf))%", systemImage: "percent")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
                if let waist = m.waistIn {
                    Label("\(String(format: "%.1f", waist))″ waist", systemImage: "ruler")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }
            if let notes = m.notes, !notes.isEmpty {
                Text(notes)
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
    }
}

// MARK: - Summary card

/// Shows the derived data — current weight, BMR × activity = TDEE, current daily targets,
/// and active goal (if any). Makes the user's inputs visibly affect outputs.
struct SummaryCard: View {
    let profile: UserProfile
    let latestMeasurement: BodyMeasurement?
    var dynamicTDEE: BodyCompositionService.TDEEResult? = nil

    private var currentWeight: Double? {
        latestMeasurement?.weightLb ?? profile.bodyWeightLb
    }

    private var bmr: Double? {
        BodyCompositionService.bmr(from: profile, currentWeightLb: currentWeight)
    }

    private var tdee: Double? {
        BodyCompositionService.tdee(from: profile, currentWeightLb: currentWeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            weightRow
            Divider().padding(.vertical, Spacing.xs)
            if let bmr, let tdee {
                energyBreakdown(bmr: bmr, tdee: tdee)
                if let dyn = dynamicTDEE?.dynamicTDEE {
                    dynamicTDEERow(value: dyn)
                }
                Divider().padding(.vertical, Spacing.xs)
                targetsRow
            } else {
                incompleteProfileRow
            }

            if let goal = profile.currentGoal, goal.isActive {
                Divider().padding(.vertical, Spacing.xs)
                activeGoalRow(goal: goal)
            }
        }
        .padding(Spacing.md)
        .mCard()
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private var weightRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Current weight")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
                if let w = currentWeight {
                    Text("\(String(format: "%.1f", w)) lb")
                        .font(.mTitle3)
                        .foregroundStyle(Color.mTextPrimary)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.mTitle3)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }
            Spacer()
            if let latestMeasurement {
                Text(latestMeasurement.recordedAt, format: .dateTime.month().day())
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
    }

    @ViewBuilder
    private func dynamicTDEERow(value: Double) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Today's actual")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
                Spacer()
                Text("\(Int(value)) kcal")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mOnTarget)
                    .monospacedDigit()
            }
            Text("Active energy from Health is an estimate; do not rely on it for precise calorie balancing.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.mTextTertiary)
        }
    }

    @ViewBuilder
    private func energyBreakdown(bmr: Double, tdee: Double) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("TDEE")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextSecondary)
                Spacer()
                Text("\(Int(tdee)) kcal/day")
                    .font(.mHeadline)
                    .foregroundStyle(Color.mTextPrimary)
                    .monospacedDigit()
            }
            Text("BMR \(Int(bmr)) × \(profile.activityLevel.displayName) \(String(format: "%.2f", profile.activityLevel.multiplier))")
                .font(.mCaption)
                .foregroundStyle(Color.mTextTertiary)
        }
    }

    @ViewBuilder
    private var targetsRow: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Daily targets")
                .font(.mCaption)
                .foregroundStyle(Color.mTextTertiary)
            HStack(spacing: Spacing.lg) {
                stat("Calories", "\(Int(profile.calorieTarget))")
                stat("Protein", "\(Int(profile.proteinTargetG))g")
                stat("Fiber", "\(Int(profile.fiberTargetG))g")
            }
        }
    }

    @ViewBuilder
    private func activeGoalRow(goal: WeightGoal) -> some View {
        HStack {
            Image(systemName: "target")
                .foregroundStyle(Color.mAccent)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let target = goal.targetWeightLb {
                    Text("Goal: \(String(format: "%.1f", target)) lb")
                        .font(.mSubheadline)
                        .foregroundStyle(Color.mTextPrimary)
                }
                Text("by \(goal.targetDate, format: .dateTime.month().day().year())")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var incompleteProfileRow: some View {
        Label("Complete your profile (height, age, sex, activity) in Settings for a personalized TDEE.", systemImage: "info.circle")
            .font(.mCaption)
            .foregroundStyle(Color.mTextSecondary)
    }

    @ViewBuilder
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.mBody)
                .foregroundStyle(Color.mTextPrimary)
                .monospacedDigit()
            Text(label)
                .font(.mCaption)
                .foregroundStyle(Color.mTextTertiary)
        }
    }
}
