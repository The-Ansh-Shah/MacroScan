import SwiftUI
import SwiftData

/// Extracted shared disclaimer so every goal-planning surface stays in lockstep.
/// Exact wording is a hard requirement from INSTRUCTIONS.md §12.3.
enum GoalPlanning {
    static let disclaimer = "This is an estimate for personal tracking. Consult a physician or registered dietitian before significant dietary changes, especially if you have underlying health conditions."
}

/// User enters a target weight + target date. Runs it through BodyCompositionService,
/// renders the plan with all safety warnings, and lets the user apply the targets to their profile.
struct GoalPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMeasurement.recordedAt, order: .reverse)
    private var measurements: [BodyMeasurement]

    enum GoalType: String, CaseIterable {
        case weight = "Weight"
        case bodyFat = "Body Fat"
    }

    @State private var goalType: GoalType = .weight
    @State private var targetWeightText: String = ""
    @State private var targetBodyFatText: String = ""
    @State private var targetDate: Date = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
    @State private var showingCriticalConfirm = false
    @State private var pendingPlanToApply: DeficitPlan?

    private var profile: UserProfile? { profiles.first }

    private var currentWeight: Double? {
        measurements.first?.weightLb ?? profile?.bodyWeightLb
    }

    private var currentBodyFat: Double? {
        guard let latest = measurements.first else { return nil }
        return latest.bodyFatPct ?? BodyCompositionService.currentBodyFat(profile: profiles.first ?? UserProfile(), latest: latest)?.pct
    }

    /// Maintenance calories measured from the user's own intake-vs-trend data, when there's
    /// enough logging history. Nil falls the plan back to the Mifflin-St Jeor estimate.
    private var rawEmpiricalTDEE: Double? {
        let repo = FoodRepository(modelContext: modelContext)
        return BodyCompositionService.empiricalTDEE(
            intakeByDay: repo.trailingDailyIntake(days: 28),
            trendWeights: BodyCompositionService.trendWeights(from: measurements)
        )
    }

    /// TDEE used to build the plan: empirical blended toward Mifflin by logging confidence.
    private var planTDEE: Double? {
        guard let profile, let w = currentWeight else { return rawEmpiricalTDEE }
        let repo = FoodRepository(modelContext: modelContext)
        let loggedDays = repo.trailingDailyIntake(days: 28).count
        let mifflin = BodyCompositionService.tdee(from: profile, currentWeightLb: w)
        return BodyCompositionService.blendedTDEE(empirical: rawEmpiricalTDEE, mifflin: mifflin, loggedDays: loggedDays)
    }

    private var plan: DeficitPlan? {
        guard let profile, let current = currentWeight, current > 0 else { return nil }

        let targetWeight: Double
        switch goalType {
        case .weight:
            guard let t = Double(targetWeightText), t > 0 else { return nil }
            targetWeight = t
        case .bodyFat:
            guard let tbf = Double(targetBodyFatText), tbf > 0,
                  let cbf = currentBodyFat, cbf > 0 else { return nil }
            let lbm = current * (1 - cbf / 100)
            targetWeight = lbm / (1 - tbf / 100)
        }

        return BodyCompositionService.computeDeficitPlan(
            profile: profile,
            currentWeightLb: current,
            targetWeightLb: targetWeight,
            targetDate: targetDate,
            currentBodyFatPct: currentBodyFat,
            tdeeOverride: planTDEE
        )
    }

    var body: some View {
        Form {
            if profile == nil {
                Text("Loading profile…")
                    .foregroundStyle(Color.mTextSecondary)
            } else if currentWeight == nil {
                profileIncompleteSection
            } else {
                basisSection
                inputsSection

                if let plan {
                    planSection(plan)
                    if !plan.warnings.isEmpty {
                        warningsSection(plan.warnings)
                    }
                    applyButtonSection(plan)
                }

                disclaimerSection
            }
        }
        .keyboardDoneButton()
        .navigationTitle("Goal Planner")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Plan carries critical warnings", isPresented: $showingCriticalConfirm) {
            Button("Adjust timeline", role: .cancel) {
                pendingPlanToApply = nil
            }
            Button("I understand — apply anyway", role: .destructive) {
                if let plan = pendingPlanToApply { applyTargets(plan) }
                pendingPlanToApply = nil
            }
        } message: {
            Text("This plan hits one or more safety floors. You can still apply it, but the goal will be flagged as unsafe.")
        }
    }

    // MARK: - Sections

    /// Shows the inputs that drive the recommendation so the user understands *why*.
    @ViewBuilder
    private var basisSection: some View {
        Section("Based on your profile") {
            if let profile, let weight = currentWeight,
               let bmr = BodyCompositionService.bmr(from: profile, currentWeightLb: weight),
               let tdee = BodyCompositionService.tdee(from: profile, currentWeightLb: weight) {
                basisRow("Weight", "\(String(format: "%.1f", weight)) lb")
                if let bf = currentBodyFat {
                    basisRow("Body fat", "\(String(format: "%.1f", bf))%")
                }
                if let h = profile.heightIn { basisRow("Height", "\(String(format: "%.1f", h))\"") }
                if let a = profile.ageYears { basisRow("Age", "\(a)") }
                basisRow("Sex", profile.biologicalSex.displayName)
                basisRow("Activity", profile.activityLevel.displayName)
                basisRow("BMR", "\(Int(bmr)) kcal")
                basisRow("TDEE", "\(Int(tdee)) kcal")
                if let adaptive = rawEmpiricalTDEE {
                    basisRow("Adaptive TDEE", "\(Int(adaptive)) kcal")
                }
            } else {
                Label("Profile incomplete — fill out Settings → Profile for a personalized plan.", systemImage: "info.circle")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
            }
        }
    }

    @ViewBuilder
    private func basisRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.mCaption).foregroundStyle(Color.mTextSecondary)
            Spacer()
            Text(value).font(.mCaption).foregroundStyle(Color.mTextPrimary).monospacedDigit()
        }
    }

    @ViewBuilder
    private var profileIncompleteSection: some View {
        Section {
            Label("Log a current weight in Body Composition first, then return here for a personalized plan.", systemImage: "info.circle")
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
        }
    }

    @ViewBuilder
    private var inputsSection: some View {
        Section("Goal") {
            Picker("Goal type", selection: $goalType) {
                ForEach(GoalType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Current weight").font(.mBody)
                Spacer()
                if let w = currentWeight {
                    Text("\(String(format: "%.1f", w)) lb")
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                        .monospacedDigit()
                }
            }

            switch goalType {
            case .weight:
                HStack {
                    Text("Target weight").font(.mBody)
                    Spacer()
                    TextField("lb", text: $targetWeightText)
                        #if canImport(UIKit)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("lb").font(.mBody).foregroundStyle(Color.mTextSecondary)
                }
            case .bodyFat:
                if currentBodyFat == nil {
                    Label("Body fat goals require a current BF% measurement. Log one in Me → Log Measurement first.", systemImage: "info.circle")
                        .font(.mCaption)
                        .foregroundStyle(Color.mApproaching)
                } else {
                    if let cbf = currentBodyFat {
                        HStack {
                            Text("Current BF%").font(.mBody)
                            Spacer()
                            Text("\(String(format: "%.1f", cbf))%")
                                .font(.mBody)
                                .foregroundStyle(Color.mTextSecondary)
                                .monospacedDigit()
                        }
                    }
                    HStack {
                        Text("Target BF%").font(.mBody)
                        Spacer()
                        TextField("%", text: $targetBodyFatText)
                            #if canImport(UIKit)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("%").font(.mBody).foregroundStyle(Color.mTextSecondary)
                    }
                }
            }

            DatePicker("Target date", selection: $targetDate, in: Date()..., displayedComponents: [.date])
        }
    }

    @ViewBuilder
    private func planSection(_ plan: DeficitPlan) -> some View {
        Section("Nutrition Plan") {
            planRow(
                "Projected change",
                value: "\(String(format: "%+.2f", -plan.projectedWeeklyLossLb)) lb / week"
            )
            planRow("Daily calories", value: "\(Int(plan.dailyCalorieTarget)) cal")
            planRow("Daily protein", value: "\(Int(plan.dailyProteinTargetG)) g")
        }

        Section("Activity Targets") {
            planRow("Daily steps", value: "\(plan.dailyStepTarget)")
            planRow("Training sessions", value: "\(plan.trainingFrequencyPerWeek) / week")
            Text(plan.trainingNote)
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
            Text("For workout tracking, use a dedicated app like Hevy. This is just a target.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.mTextTertiary)
        }
    }

    @ViewBuilder
    private func warningsSection(_ warnings: [SafetyWarning]) -> some View {
        Section("Warnings") {
            ForEach(warnings) { warning in
                WarningBanner(warning: warning)
            }
        }
    }

    @ViewBuilder
    private func applyButtonSection(_ plan: DeficitPlan) -> some View {
        Section {
            Button {
                if plan.isSafe {
                    applyTargets(plan)
                } else {
                    pendingPlanToApply = plan
                    showingCriticalConfirm = true
                    Haptics.warning()
                }
            } label: {
                Label("Apply these targets", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .font(.mHeadline)
            }
            .buttonStyle(.borderedProminent)
            .tint(plan.isSafe ? Color.mAccent : Color.mOver)
        }
    }

    @ViewBuilder
    private var disclaimerSection: some View {
        Section {
            Text(GoalPlanning.disclaimer)
                .font(.mCaption)
                .foregroundStyle(Color.mTextTertiary)
        }
    }

    @ViewBuilder
    private func planRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.mBody)
            Spacer()
            Text(value)
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
                .monospacedDigit()
        }
    }

    // MARK: - Actions

    private func applyTargets(_ plan: DeficitPlan) {
        guard let profile, let current = currentWeight else { return }

        let targetWeightLb: Double
        let targetBFPct: Double?
        switch goalType {
        case .weight:
            guard let t = Double(targetWeightText), t > 0 else { return }
            targetWeightLb = t
            targetBFPct = nil
        case .bodyFat:
            guard let tbf = Double(targetBodyFatText), tbf > 0,
                  let cbf = currentBodyFat, cbf > 0 else { return }
            let lbm = current * (1 - cbf / 100)
            targetWeightLb = lbm / (1 - tbf / 100)
            targetBFPct = tbf
        }

        profile.calorieTarget = plan.dailyCalorieTarget
        profile.proteinTargetG = plan.dailyProteinTargetG
        profile.dailyStepTarget = plan.dailyStepTarget

        // Deactivate any prior active goals before creating a new one.
        let priorActive = FetchDescriptor<WeightGoal>(predicate: #Predicate { $0.isActive })
        for prior in (try? modelContext.fetch(priorActive)) ?? [] {
            prior.isActive = false
        }

        let goal = WeightGoal(
            targetWeightLb: targetWeightLb,
            targetBodyFatPct: targetBFPct,
            targetDate: targetDate,
            isActive: true,
            startingWeightLb: current,
            startingBodyFatPct: currentBodyFat
        )
        modelContext.insert(goal)
        profile.currentGoal = goal

        Haptics.targetHit()
        dismiss()
    }
}

// MARK: - Warning banner

struct WarningBanner: View {
    let warning: SafetyWarning

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(warning.title)
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextPrimary)
                Text(warning.message)
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint, lineWidth: warning.severity == .critical ? 1.5 : 0.5)
        )
    }

    private var symbol: String {
        switch warning.severity {
        case .critical: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    private var tint: Color {
        switch warning.severity {
        case .critical: return .mOver
        case .warning: return .mApproaching
        case .info: return .mAccent
        }
    }

    private var background: Color {
        switch warning.severity {
        case .critical: return Color.mOver.opacity(0.12)
        case .warning: return Color.mApproaching.opacity(0.12)
        case .info: return Color.mBgSecondary
        }
    }
}
