import Foundation

/// Pure computation for body composition + goal planning.
/// No AI, no persistence — callers pass in the UserProfile + target values.
///
/// All energy math uses Mifflin-St Jeor BMR → TDEE multiplier → deficit plan,
/// with hard safety rails per INSTRUCTIONS.md §12.3.
enum BodyCompositionService {

    // MARK: - BMR / TDEE

    /// Mifflin-St Jeor basal metabolic rate (kcal/day).
    /// Returns nil if profile is missing required inputs (weight, height, age, sex).
    static func bmr(from profile: UserProfile, currentWeightLb: Double? = nil) -> Double? {
        guard let heightIn = profile.heightIn,
              let ageYears = profile.ageYears,
              let weightLb = currentWeightLb ?? profile.bodyWeightLb,
              heightIn > 0, ageYears > 0, weightLb > 0 else {
            return nil
        }
        let weightKg = weightLb * 0.453592
        let heightCm = heightIn * 2.54

        // Mifflin-St Jeor:
        // Men:   10·kg + 6.25·cm − 5·age + 5
        // Women: 10·kg + 6.25·cm − 5·age − 161
        // Unspecified: average of the two
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears)
        switch profile.biologicalSex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78  // midpoint of +5 and -161
        }
    }

    /// Total daily energy expenditure = BMR × activity multiplier.
    static func tdee(from profile: UserProfile, currentWeightLb: Double? = nil) -> Double? {
        guard let bmr = bmr(from: profile, currentWeightLb: currentWeightLb) else { return nil }
        return bmr * profile.activityLevel.multiplier
    }

    // MARK: - Dynamic TDEE

    struct TDEEResult {
        let staticTDEE: Double
        let dynamicTDEE: Double?
        let activeEnergyToday: Double?
        let basalEnergyToday: Double?
    }

    static func todaysTDEE(
        profile: UserProfile,
        currentWeightLb: Double?,
        activeEnergy: Double?,
        basalEnergy: Double?
    ) -> TDEEResult? {
        guard let staticVal = tdee(from: profile, currentWeightLb: currentWeightLb) else { return nil }
        guard let bmrVal = bmr(from: profile, currentWeightLb: currentWeightLb) else {
            return TDEEResult(staticTDEE: staticVal, dynamicTDEE: nil, activeEnergyToday: nil, basalEnergyToday: nil)
        }

        var dynamicTDEE: Double? = nil
        if let active = activeEnergy, let basal = basalEnergy, (active + basal) > 0 {
            dynamicTDEE = basal + active
        } else if let active = activeEnergy, active > 0 {
            dynamicTDEE = bmrVal + active
        }

        return TDEEResult(
            staticTDEE: staticVal,
            dynamicTDEE: dynamicTDEE,
            activeEnergyToday: activeEnergy,
            basalEnergyToday: basalEnergy
        )
    }

    // MARK: - Body Fat Estimation (Navy Method)

    enum BodyFatEstimationError: Error, LocalizedError {
        case missingMeasurement(field: String)
        case invalidMeasurement(field: String)
        case sexNotSpecified

        var errorDescription: String? {
            switch self {
            case .missingMeasurement(let f): return "\(f) is required for body fat estimation."
            case .invalidMeasurement(let f): return "\(f) has an invalid value."
            case .sexNotSpecified: return "Biological sex is required for the Navy Method."
            }
        }
    }

    enum Confidence { case high, medium, low }

    struct BodyFatEstimate {
        let pct: Double
        let source: BodyFatSource
        let confidence: Confidence
    }

    static func estimateBodyFatNavy(
        sex: BiologicalSex,
        heightIn: Double,
        waistIn: Double,
        neckIn: Double,
        hipIn: Double?
    ) throws -> BodyFatEstimate {
        guard sex != .unspecified else { throw BodyFatEstimationError.sexNotSpecified }
        guard heightIn >= 10 && heightIn <= 100 else { throw BodyFatEstimationError.invalidMeasurement(field: "Height") }
        guard waistIn >= 10 && waistIn <= 100 else { throw BodyFatEstimationError.invalidMeasurement(field: "Waist") }
        guard neckIn >= 10 && neckIn <= 100 else { throw BodyFatEstimationError.invalidMeasurement(field: "Neck") }

        let pct: Double
        switch sex {
        case .male:
            guard waistIn > neckIn else { throw BodyFatEstimationError.invalidMeasurement(field: "Waist must be larger than neck") }
            pct = 86.010 * log10(waistIn - neckIn) - 70.041 * log10(heightIn) + 36.76
        case .female:
            guard let hip = hipIn, hip >= 10 && hip <= 100 else { throw BodyFatEstimationError.missingMeasurement(field: "Hip") }
            guard (waistIn + hip) > neckIn else { throw BodyFatEstimationError.invalidMeasurement(field: "Waist + hip must be larger than neck") }
            pct = 163.205 * log10(waistIn + hip - neckIn) - 97.684 * log10(heightIn) - 78.387
        case .unspecified:
            throw BodyFatEstimationError.sexNotSpecified
        }

        let rounded = (pct * 10).rounded() / 10
        return BodyFatEstimate(pct: max(1, rounded), source: .navy, confidence: .high)
    }

    static func currentBodyFat(profile: UserProfile, latest: BodyMeasurement?) -> BodyFatEstimate? {
        if let bf = latest?.bodyFatPct, bf > 0 {
            let src = latest?.bodyFatSource ?? .manual
            return BodyFatEstimate(pct: bf, source: src, confidence: src == .navy ? .high : .medium)
        }
        if let heightIn = profile.heightIn,
           let waist = latest?.waistIn,
           let neck = latest?.neckIn,
           profile.biologicalSex != .unspecified {
            return try? estimateBodyFatNavy(
                sex: profile.biologicalSex,
                heightIn: heightIn,
                waistIn: waist,
                neckIn: neck,
                hipIn: latest?.hipIn
            )
        }
        return nil
    }

    // MARK: - Deficit planning

    /// Build a DeficitPlan for the given goal. Enforces all hard safety rails.
    static func computeDeficitPlan(
        profile: UserProfile,
        currentWeightLb: Double,
        targetWeightLb: Double,
        targetDate: Date,
        currentBodyFatPct: Double? = nil
    ) -> DeficitPlan {
        let today = Calendar.current.startOfDay(for: Date())
        let targetDay = Calendar.current.startOfDay(for: targetDate)
        let timelineDays = max(1, Calendar.current.dateComponents([.day], from: today, to: targetDay).day ?? 1)

        let totalLbToLose = currentWeightLb - targetWeightLb
        let isLoss = totalLbToLose > 0

        var warnings: [SafetyWarning] = []

        // TDEE (may be nil if profile incomplete)
        guard let tdee = tdee(from: profile, currentWeightLb: currentWeightLb) else {
            return DeficitPlan(
                dailyCalorieTarget: profile.calorieTarget,
                dailyProteinTargetG: profile.proteinTargetG,
                projectedWeeklyLossLb: 0,
                warnings: [.info("Complete your profile (height, age, sex) in Settings for a personalized plan.")],
                isSafe: true,
                dailyStepTarget: stepTargetForActivity(profile.activityLevel),
                trainingFrequencyPerWeek: 4,
                trainingNote: "Complete your profile for a personalized training recommendation."
            )
        }

        // 3500 kcal ≈ 1 lb of body fat
        let totalDeficitKcal = totalLbToLose * 3500
        let rawDailyDeficit = totalDeficitKcal / Double(timelineDays)
        var dailyCalorieTarget = tdee - rawDailyDeficit

        // Rule 1: Calorie floor
        let floor: Double = {
            let absoluteFloor: Double = profile.biologicalSex == .female ? 1200 : 1500
            let relativeFloor = 10 * currentWeightLb
            return max(absoluteFloor, relativeFloor)
        }()
        if isLoss && dailyCalorieTarget < floor {
            warnings.append(.calorieFloorBreached(floor: floor))
            dailyCalorieTarget = floor
        }

        // Rule 5: Minimum timeline — deficit > 25% of TDEE
        if isLoss && rawDailyDeficit > tdee * 0.25 {
            // Min days that keep the deficit ≤ 20% of TDEE
            let safeDailyDeficit = tdee * 0.20
            let minDays = Int(ceil(totalDeficitKcal / safeDailyDeficit))
            warnings.append(.timelineTooAggressive(recommendedMinDays: minDays))
        }

        // Rule 2: Weekly loss cap — 1% of bodyweight per week
        let projectedWeeklyLossLb = isLoss
            ? (rawDailyDeficit * 7) / 3500
            : -((abs(rawDailyDeficit) * 7) / 3500)
        let safeMaxLossLb = currentWeightLb * 0.01
        if isLoss && projectedWeeklyLossLb > safeMaxLossLb {
            warnings.append(.weeklyLossTooFast(
                currentLbPerWeek: projectedWeeklyLossLb,
                safeMax: safeMaxLossLb
            ))
        }

        // Rule 3: Protein floor — 0.7g/lb minimum, 0.75g/lb recommended
        let recommendedProteinG = currentWeightLb * 0.75
        let proteinFloor = currentWeightLb * 0.7
        let dailyProteinTargetG = max(recommendedProteinG, proteinFloor)
        if dailyProteinTargetG < proteinFloor {
            warnings.append(.proteinTooLow(minimum: proteinFloor))
        }

        // Rule 4: Body fat floor — warn if already low
        if let bf = currentBodyFatPct {
            let threshold: Double = profile.biologicalSex == .female ? 18 : 10
            if bf < threshold {
                warnings.append(.bodyFatAlreadyLow(currentPct: bf))
            }
        }

        let hasCritical = warnings.contains { $0.severity == .critical }

        let stepTarget = stepTargetForActivity(profile.activityLevel)
        let (trainingFreq, trainingNote) = trainingRecommendation(
            dietGoal: profile.dietGoal,
            deficitPct: isLoss ? rawDailyDeficit / tdee : 0
        )

        return DeficitPlan(
            dailyCalorieTarget: dailyCalorieTarget,
            dailyProteinTargetG: dailyProteinTargetG,
            projectedWeeklyLossLb: projectedWeeklyLossLb,
            warnings: warnings,
            isSafe: !hasCritical,
            dailyStepTarget: stepTarget,
            trainingFrequencyPerWeek: trainingFreq,
            trainingNote: trainingNote
        )
    }

    private static func stepTargetForActivity(_ level: ActivityLevel) -> Int {
        switch level {
        case .sedentary:        return 7500
        case .lightlyActive:    return 8500
        case .moderatelyActive: return 10000
        case .veryActive:       return 12000
        case .extremelyActive:  return 12500
        }
    }

    private static func trainingRecommendation(
        dietGoal: DietGoal,
        deficitPct: Double
    ) -> (freq: Int, note: String) {
        switch dietGoal {
        case .cut:
            let freq = deficitPct > 0.20 ? 3 : 4
            return (freq, "\(freq) strength sessions per week, 45-60 min, focus on compound lifts to preserve muscle. Add 1-2 light cardio days for recovery.")
        case .maintain:
            return (4, "4-5 strength sessions per week, 60 min, progressive overload.")
        case .bulk:
            return (5, "4-5 strength sessions per week, 60-75 min, focus on adding weight or reps each session.")
        }
    }
}

// MARK: - Plan + Safety types

struct DeficitPlan {
    var dailyCalorieTarget: Double
    var dailyProteinTargetG: Double
    var projectedWeeklyLossLb: Double
    var warnings: [SafetyWarning]
    var isSafe: Bool
    var dailyStepTarget: Int
    var trainingFrequencyPerWeek: Int
    var trainingNote: String
}

enum SafetyWarning: Identifiable {
    case timelineTooAggressive(recommendedMinDays: Int)
    case calorieFloorBreached(floor: Double)
    case proteinTooLow(minimum: Double)
    case bodyFatAlreadyLow(currentPct: Double)
    case weeklyLossTooFast(currentLbPerWeek: Double, safeMax: Double)
    case info(String)

    enum Severity { case info, warning, critical }

    var severity: Severity {
        switch self {
        case .timelineTooAggressive, .calorieFloorBreached, .weeklyLossTooFast:
            return .critical
        case .proteinTooLow, .bodyFatAlreadyLow:
            return .warning
        case .info:
            return .info
        }
    }

    var id: String {
        switch self {
        case .timelineTooAggressive(let d): return "timeline-\(d)"
        case .calorieFloorBreached(let f): return "floor-\(Int(f))"
        case .proteinTooLow(let m): return "protein-\(Int(m))"
        case .bodyFatAlreadyLow(let p): return "bf-\(Int(p))"
        case .weeklyLossTooFast(let c, _): return "loss-\(Int(c * 100))"
        case .info(let s): return "info-\(s.hashValue)"
        }
    }

    var title: String {
        switch self {
        case .timelineTooAggressive: return "Timeline too aggressive"
        case .calorieFloorBreached: return "Calorie floor reached"
        case .proteinTooLow: return "Protein below floor"
        case .bodyFatAlreadyLow: return "Body fat already low"
        case .weeklyLossTooFast: return "Weekly loss rate too fast"
        case .info(let s): return s
        }
    }

    var message: String {
        switch self {
        case .timelineTooAggressive(let days):
            return "This plan requires a deficit greater than 25% of your TDEE. Extend the timeline to at least \(days) days for a sustainable deficit (≤20% of TDEE)."
        case .calorieFloorBreached(let floor):
            return "The plan hits a safety floor of \(Int(floor)) kcal/day. Eating below this consistently is not recommended without medical supervision."
        case .proteinTooLow(let min):
            return "Protein should not go below \(Int(min))g/day during a cut to preserve muscle."
        case .bodyFatAlreadyLow(let pct):
            return "Your current body fat (\(String(format: "%.1f", pct))%) is already low. Further cutting may carry hormonal and health risks."
        case .weeklyLossTooFast(let current, let safe):
            return "Planned loss: \(String(format: "%.2f", current)) lb/week. The safe maximum is \(String(format: "%.2f", safe)) lb/week (1% of bodyweight)."
        case .info(let s):
            return s
        }
    }
}
