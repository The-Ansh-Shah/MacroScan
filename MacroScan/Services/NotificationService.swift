import Foundation
import UserNotifications

/// Local-only notifications (no server, no remote push). Schedules two kinds of
/// repeating reminders, both computed from CURRENT data at schedule time:
///   • Goal pings (~3×/day) — calorie/protein progress vs targets.
///   • Activity nudge (1×/day) — movement reminder varied by today's step count.
///
/// Content is baked in when scheduled (iOS local notifications are static once
/// queued); `reschedule(profile:repo:)` is re-run on launch so the next day's
/// pings reflect fresh data.
@MainActor
enum NotificationService {

    /// Identifiers we own — used so we never touch notifications from elsewhere.
    private static let activityNudgeID = "activity-nudge"
    private static func goalPingID(hour: Int) -> String { "goal-ping-\(hour)" }

    private static var ownedIdentifiers: [String] {
        // Cover any hour 0...23 so we clean up stale pings if the user changes hours.
        (0...23).map(goalPingID(hour:)) + [activityNudgeID]
    }

    // MARK: - Authorization

    /// Request alert/sound/badge permission. Returns whether it was granted.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    /// Remove our pending requests and re-add them from current profile + log data.
    static func reschedule(profile: UserProfile, repo: FoodRepository) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ownedIdentifiers)

        guard profile.notificationsEnabled else { return }

        scheduleGoalPings(profile: profile, repo: repo, center: center)
        await scheduleActivityNudge(profile: profile, center: center)
    }

    /// Remove all of our notifications (used when the user disables them).
    static func cancelAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ownedIdentifiers)
    }

    // MARK: - Goal pings

    private static func scheduleGoalPings(
        profile: UserProfile,
        repo: FoodRepository,
        center: UNUserNotificationCenter
    ) {
        let totals = repo.dailyTotals(forDate: Date())
        let goalHint = goalProgressHint(profile: profile, repo: repo)

        for hour in Set(profile.goalPingHours) where (0...23).contains(hour) {
            let content = UNMutableNotificationContent()
            content.title = "Macro check-in"
            content.body = goalPingBody(totals: totals, profile: profile, hint: goalHint)
            content.sound = .default

            var components = DateComponents()
            components.hour = hour
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            let request = UNNotificationRequest(
                identifier: goalPingID(hour: hour),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private static func goalPingBody(totals: ScaledMacros, profile: UserProfile, hint: String?) -> String {
        var pieces: [String] = []

        if profile.proteinTargetG > 0 {
            let pct = Int((totals.proteinG / profile.proteinTargetG * 100).rounded())
            pieces.append("\(pct)% of protein")
        }
        if profile.calorieTarget > 0 {
            let cal = Int(totals.calories.rounded())
            let target = Int(profile.calorieTarget.rounded())
            pieces.append("\(formatted(cal))/\(formatted(target)) cal")
        }

        var body = pieces.isEmpty ? "Time to log your meals." : pieces.joined(separator: ", ")
        if let hint { body += " — \(hint)" }
        return body
    }

    /// On-track / behind hint derived from the active weight goal, if any.
    ///
    /// Uses `BodyCompositionService.projectGoal` over the trend-weight series built
    /// from the latest measurement we can read through the repo. A full measurement
    /// history would yield a sharper slope, but `FoodRepository` only exposes the
    /// latest sample publicly, so we project from current weight vs target — enough
    /// for a short on-track / behind nudge.
    private static func goalProgressHint(profile: UserProfile, repo: FoodRepository) -> String? {
        guard let goal = profile.currentGoal, goal.isActive,
              let currentLb = repo.currentWeightLb(profile: profile) else { return nil }

        let latest = repo.latestBodyMeasurement()
        let trend: [(date: Date, lb: Double)] = [(date: latest?.recordedAt ?? Date(), lb: currentLb)]

        let intake = repo.trailingDailyIntake(days: 28)
        let empirical = BodyCompositionService.empiricalTDEE(intakeByDay: intake, trendWeights: trend)
        let projection = BodyCompositionService.projectGoal(
            goal: goal,
            trendWeights: trend,
            empiricalTDEE: empirical
        )

        switch projection.status {
        case .onTrack:        return "on track"
        case .ahead:          return "ahead of plan"
        case .behind:         return "behind plan, stay tight"
        // Stalled/insufficient-slope (e.g. single data point) reads as
        // `.wrongDirection`; suppress rather than show a misleading nudge.
        case .wrongDirection, .noData: return nil
        }
    }

    // MARK: - Activity nudge

    private static func scheduleActivityNudge(
        profile: UserProfile,
        center: UNUserNotificationCenter
    ) async {
        guard profile.activityNudgeEnabled, (0...23).contains(profile.activityNudgeHour) else { return }

        let steps = (try? await HealthKitService.shared.stepCount(forDate: Date())) ?? 0

        let content = UNMutableNotificationContent()
        content.title = "Move today"
        content.body = activityNudgeBody(steps: steps, target: profile.dailyStepTarget)
        content.sound = .default

        var components = DateComponents()
        components.hour = profile.activityNudgeHour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: activityNudgeID,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    private static func activityNudgeBody(steps: Int, target: Int) -> String {
        let goal = target > 0 ? target : 8000
        if steps >= goal {
            return "Nice work today. Walk, stretch, or rest — your call."
        } else if steps >= goal / 2 {
            return "Good day for some movement. Now's a good window."
        } else {
            return "Go for a walk or run today — even a short one counts."
        }
    }

    // MARK: - Helpers

    private static func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
