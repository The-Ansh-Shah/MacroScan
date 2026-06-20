# MacroScan — Build Instructions (Iteration 2)

Reference: [ARCHITECTURE.md](ARCHITECTURE.md), [PROGRESS.md](PROGRESS.md)

This document specifies the next build iteration. It adds: day-based organization, delete/edit functionality, text search with ingredient substitutions, body composition tracking, goal planning, and safety guardrails.

**Read this entire document before beginning. Update `PROGRESS.md` as items are completed (check off and mark phase complete).**

---

## Context

Core app is functional. The user has flagged the following as immediate needs:

1. **No way to remove logged food items** — swipe-to-delete exists on MealSectionView per PROGRESS, but the user reports it isn't working or discoverable. Audit and make deletion work reliably across all views.
2. **Food should be organized by day** — currently seems to only show today. Need historical day-by-day view that's the primary organizational model.
3. **Text search for specific foods + modification** — e.g., "Taco Bell chalupa with refried beans instead of beef." Must handle both lookup and per-ingredient substitution.
4. **Body composition tracking + goal-driven diet planning** — user enters current weight, body fat %, goal, and timeline; app computes macros. Requires safety rails.
5. **AI error resilience** — Gemini intermittently returns "model experiencing high demand." Need retry + graceful fallback.
6. **Proactive safety warnings** — if daily intake is skewed (e.g., way over fat, way under fiber), surface it. If goal timeline requires unsafe deficit, warn clearly.

---

## Phase 9 — Log Management

### 9.1 Audit existing delete
- Verify swipe-to-delete on `MealSectionView` actually works. If broken, fix.
- Verify it calls `FoodRepository.delete(logEntry:)` correctly and animates out.
- Confirm haptic fires on delete (`.impact(.rigid)`).

### 9.2 Add edit for log entries
- Long-press on a `FoodRow` in a meal section → presents an action sheet: **Edit**, **Delete**, **Cancel**.
- Edit opens an `EditLogEntrySheet` — same layout as `ManualFoodForm` but pre-filled with the entry's values. Saving updates the `LogEntry` in place (not creating a new one).
- Deletion from action sheet also works (parity with swipe).

### 9.3 Bulk delete (optional this phase)
- On a day view with multiple entries, a toolbar "Edit" button enters multi-select; user can delete multiple at once.
- Defer if time-constrained — move to Phase 12.

---

## Phase 10 — Day-Based Organization

### 10.1 Rename `TodayView` to `DayView`
- `DayView` takes a `Date` parameter (defaults to today when presented from the Today tab).
- All aggregation logic in `FoodRepository` should already be date-parameterized — verify `entries(forDate:)` and `dailyTotals(forDate:)` exist and are used.

### 10.2 Today tab: horizontal date scroller
- At the top of the Today tab, a horizontal scrollable row showing dates — last 14 days by default, today centered/rightmost on first open.
- Each date shows: day abbreviation (Mon/Tue/...), day of month, and a small colored dot indicating macro target hit state (green = all macros within targets, orange = close, gray = under, red = calorie exceeded).
- Tapping a date swaps the `DayView` to show that day's entries.
- Scrolling left reveals older days. Infinite scroll back; cap at user's earliest logged entry.
- Selected date highlighted with `Color.mAccent` background.

### 10.3 History tab rework
- `HistoryView` becomes the "all days" browser: vertical list of days (most recent at top), each row summarizing calories / protein / fiber for that day, tappable to open `DayView` for that date.
- The existing 7-day charts move into a "Trends" subsection or a separate top tab within History. Do not delete the charts — they're valuable.

### 10.4 Day navigation within `DayView`
- Left/right chevron buttons in the `DayView` navigation bar to step to previous/next day.
- Disabled states when no prior/next day has entries (but still allows viewing today even if empty).

---

## Phase 11 — Text Search & Ingredient Substitutions

### 11.1 Add a `FoodSearchService`
- New service, not an actor (pure computation over local DB + optional remote).
- `search(query: String) async -> [FoodSearchResult]`
- Sources (in order of priority):
  1. **Local `Food` table** — fuzzy match against `name` + `brand` (case-insensitive substring + simple fuzzy ranking)
  2. **Open Food Facts product search** — OFF has a search endpoint beyond barcode lookup: `https://world.openfoodfacts.org/cgi/search.pl?search_terms={q}&search_simple=1&json=1&page_size=10`. Use it when local results are thin.
- Deduplicate results: if OFF result matches an already-known Food (by name similarity), prefer the local version.
- Rank: local favorites > local frequently-eaten > local occasional > OFF remote.

### 11.2 Add `SearchView`
- Accessible from a search icon on `DayView` and from a dedicated "Add Food" FAB.
- Live-updating results as user types (debounced 250ms).
- Each result row shows: name, brand, source icon (local / OFF), macros per 100g.
- Tapping a result opens a pre-filled log sheet — same UI as `ScanResultSheet` but reusable for search.

### 11.3 Ingredient substitutions
- On the log sheet for a matched food, add an **"Customize ingredients"** disclosure section.
- Section is only enabled if the food has ingredient data (OFF provides this; not all foods will).
- Within the section, list ingredients with a toggle / replace button.
- Replacing an ingredient opens a secondary search for a substitute — user picks, and the app computes a revised macro estimate.
- **Revised macro math:** treat the original food as a recipe sum. Subtract the displaced ingredient's typical macros and add the replacement's. Use Open Food Facts for ingredient-level macros when available. If data is incomplete, show the estimate with a confidence indicator: "Approximate — ingredient swap based on typical values."
- This is an approximation, not precision. Label it clearly. Do not pretend otherwise.

### 11.4 Notes field on log entries
- `LogEntry` gains a `notes: String?` field.
- User can add free text on any log — "Taco Bell chalupa, refried beans sub, extra sauce." Useful when the substitution system can't capture the full reality.

---

## Phase 12 — Body Composition & Goal Planning

### 12.1 Data model additions

Add a new `@Model` type:

```swift
@Model
final class BodyMeasurement {
    var recordedAt: Date
    var weightLb: Double
    var bodyFatPct: Double?       // optional — user may not always measure
    var waistIn: Double?           // optional, useful secondary metric
    var notes: String?
}
```

Add to `UserProfile`:

```swift
var heightIn: Double?
var ageYears: Int?
var biologicalSex: BiologicalSex?   // new enum: male, female, unspecified
var activityLevel: ActivityLevel    // new enum
var currentGoal: WeightGoal?        // new @Model relationship
```

New enums:

```swift
enum BiologicalSex { case male, female, unspecified }
enum ActivityLevel {
    case sedentary        // 1.2 multiplier
    case lightlyActive    // 1.375
    case moderatelyActive // 1.55
    case veryActive       // 1.725
    case extremelyActive  // 1.9
}
```

New `@Model`:

```swift
@Model
final class WeightGoal {
    var startedAt: Date
    var targetWeightLb: Double?
    var targetBodyFatPct: Double?
    var targetDate: Date
    var isActive: Bool
    // Snapshot of starting state for progress tracking:
    var startingWeightLb: Double
    var startingBodyFatPct: Double?
}
```

### 12.2 `BodyCompositionService`

Pure computation. No AI.

- `computeBMR(profile, currentWeight) -> Double` — Mifflin-St Jeor equation. Requires height, age, sex. Returns kcal/day. If data is missing, return nil and caller shows "Please complete your profile in Settings."
- `computeTDEE(bmr, activity) -> Double` — BMR × activity multiplier.
- `computeRecommendedDeficit(currentWeight, targetWeight, timelineDays) -> DeficitPlan` — see safety rules below.

### 12.3 DeficitPlan + safety rails (read carefully)

```swift
struct DeficitPlan {
    var dailyCalorieTarget: Double
    var dailyProteinTargetG: Double
    var projectedWeeklyLossLb: Double
    var warnings: [SafetyWarning]
    var isSafe: Bool               // false if any .critical warnings
}

enum SafetyWarning {
    case timelineTooAggressive(recommendedMinDays: Int)
    case calorieFloorBreached(floor: Double)
    case proteinTooLow(minimum: Double)
    case bodyFatAlreadyLow(currentPct: Double)
    case weeklyLossTooFast(currentLbPerWeek: Double, safeMax: Double)
    case info(String)
    
    var severity: Severity { /* .info, .warning, .critical */ }
}
```

**Hard rules (non-negotiable):**

1. **Calorie floor:** Do not recommend targets below `max(1500, 10 * bodyWeightLb)` for men or `max(1200, 10 * bodyWeightLb)` for women. If the timeline requires it, return `.calorieFloorBreached` as a `.critical` warning. User can override but plan is marked `isSafe = false`.
2. **Weekly loss cap:** Do not recommend plans targeting more than 1% of bodyweight per week. Above that → `.weeklyLossTooFast`, severity `.critical`.
3. **Protein floor:** 0.7g per lb bodyweight minimum during a cut. Recommend 1.0g/lb. Never go below the floor.
4. **Body fat floor:** If user's current body fat is below 10% (men) / 18% (women), show `.bodyFatAlreadyLow` as `.warning`. Do not block the goal but surface it clearly.
5. **Minimum timeline:** If target requires a deficit > 25% of TDEE, return `.timelineTooAggressive` with `recommendedMinDays` that would bring the deficit to ≤ 20% of TDEE.

**Important:** These are not medical advice. Every view that surfaces goal-planning must include a footer: *"This is an estimate for personal tracking. Consult a physician or registered dietitian before significant dietary changes, especially if you have underlying health conditions."*

### 12.4 Views

- **`ProfileSetupView`** (first-launch onboarding, skippable): collects height, age, sex, activity level, current weight, current body fat (optional). User can fill in Settings later.
- **`BodyCompositionView`** (in Settings or a new "Me" tab): shows current measurements, history chart, "Log measurement" button.
- **`GoalPlannerView`**: user enters target weight or body fat + target date. Shows:
  - Projected weekly change
  - Recommended calorie + protein targets
  - All warnings, prominently
  - "Apply these targets" button — updates `UserProfile` targets; user can revert anytime
  - Footer disclaimer (see above)
- **`GoalProgressView`**: given an active `WeightGoal`, shows current progress vs. linear projection. Purely visual — no judgment about whether user is "behind."

### 12.5 Safety warning presentation
- Critical warnings shown as a red banner the user cannot dismiss without acknowledging ("I understand — apply anyway" or "Adjust timeline").
- Warning-level shown inline with orange tint.
- Info-level shown as subtle note below the plan.

---

## Phase 13 — Daily Balance Insights

### 13.1 Compute daily balance flags

Add to `FoodRepository`:

```swift
func balanceFlags(forDate: Date) -> [BalanceFlag]
```

Where `BalanceFlag` covers:
- **Protein low**: < 70% of target with day nearly over (past 6pm)
- **Fiber low**: < 50% of target with day nearly over
- **Fat excessive**: > 150% of target
- **Calorie deficit too large**: actual intake < 60% of TDEE
- **Micro deficit streak**: under B12 / iron / D target for 5+ consecutive days

Each flag has: `severity` (.info/.warning/.critical), `title`, `message`, `suggestedAction` (optional deep link to `CloseGapView` etc.)

### 13.2 Insights surface on DayView

- A collapsible "Insights" card on `DayView` when flags are present.
- Card uses the functional color system: orange border for warnings, red for critical.
- Tappable → deep link to the relevant view (e.g., "You've been under B12 for 5 days" → opens a pre-filtered search for high-B12 vegetarian foods).

### 13.3 Insights don't nag
- If user dismisses an info-level flag, suppress it for that day.
- Never show more than 2 flags at once — prioritize by severity.
- Do not show balance flags for past days the user is just reviewing (only today or the current goal window).

---

## Phase 14 — AI Resilience

### 14.1 Retry with exponential backoff in `AIVisionService`

- On Gemini 429 or "model experiencing high demand" responses, retry up to 3 times with backoff: 1s, 3s, 8s.
- Show a loading state with text updating: "Analyzing…" → "Retrying…" → "Still trying…"

### 14.2 Graceful fallback

If all retries fail:
- Show a sheet: "AI analysis isn't available right now. You can still log this manually."
- Sheet contains: the captured photo (user can see what they took), a `ManualFoodForm` pre-filled with blanks.
- Preserve the photo in the `LogEntry.photoData` field if user proceeds to manual entry.

### 14.3 Quota-aware user messaging

- If Gemini returns an explicit quota-exceeded error, show a clearer message: "AI analysis is temporarily rate-limited. This usually resolves within a few minutes."
- Log these events to a local counter visible in Settings → "AI Usage" for user debugging.

---

## Progress Updates

Add the following phases to `PROGRESS.md`. Check off each item as completed. After all phases pass their verify steps, update the final status and commit with message "Iteration 2 complete".

```markdown
## Phase 9 — Log Management
- [ ] Audit and fix swipe-to-delete on MealSectionView
- [ ] Long-press → Edit/Delete action sheet on FoodRow
- [ ] EditLogEntrySheet (reuses ManualFoodForm layout, updates in place)
- [ ] Haptic on delete (.impact(.rigid))
- [ ] **Verify:** delete works from swipe + long-press; edit updates values

## Phase 10 — Day-Based Organization
- [ ] Rename TodayView → DayView; parameterize by Date
- [ ] Horizontal date scroller at top of Today tab (14 days, target-hit dots)
- [ ] History tab: vertical list of all days, tappable to DayView
- [ ] Preserve 7-day charts as "Trends" subsection of History
- [ ] Day navigation chevrons in DayView toolbar
- [ ] **Verify:** can navigate arbitrary past days; charts still render

## Phase 11 — Text Search & Substitutions
- [ ] FoodSearchService (local DB + OFF search endpoint)
- [ ] SearchView with debounced live results
- [ ] Reusable pre-filled log sheet from search results
- [ ] Ingredient list + substitution flow (where data available)
- [ ] notes: String? field added to LogEntry
- [ ] **Verify:** text search finds real products; substitutions update macros

## Phase 12 — Body Composition & Goal Planning
- [ ] BodyMeasurement @Model
- [ ] UserProfile extended: height, age, sex, activityLevel
- [ ] WeightGoal @Model
- [ ] BiologicalSex + ActivityLevel enums
- [ ] BodyCompositionService (Mifflin-St Jeor + TDEE + deficit planning)
- [ ] DeficitPlan struct + SafetyWarning enum with all hard rules
- [ ] ProfileSetupView onboarding
- [ ] BodyCompositionView (log measurements, history chart)
- [ ] GoalPlannerView with safety warnings + required disclaimer footer
- [ ] GoalProgressView
- [ ] **Verify:** hard safety rules enforced; disclaimers present; targets apply

## Phase 13 — Daily Balance Insights
- [ ] balanceFlags(forDate:) in FoodRepository
- [ ] BalanceFlag struct + severity tiers
- [ ] Insights card on DayView (collapsible, max 2 flags)
- [ ] Deep links from flags to relevant views
- [ ] Dismiss-for-today behavior
- [ ] **Verify:** flags fire correctly; don't show on past-day review

## Phase 14 — AI Resilience
- [ ] Retry with exponential backoff (1s, 3s, 8s) on quota/demand errors
- [ ] Updated loading state text during retries
- [ ] Fallback sheet → manual form with photo preserved
- [ ] Quota-exceeded messaging
- [ ] AI Usage counter in Settings
- [ ] **Verify:** simulate Gemini failure → falls back gracefully; photo retained
```

---

## Build Order Note

Work phases in order. Each phase is independently valuable and shippable. After Phase 9 the user can manage logs properly; after Phase 10 the app is meaningfully usable historically; after Phase 11 it can handle real-world meals; after Phase 12 it earns its keep; 13 and 14 are polish.

Do not skip safety rails in Phase 12 for expediency. They are the feature, not a speed bump.

## Constraints

- Follow all conventions in `ARCHITECTURE.md` §15
- No new external packages
- Continue using Gemini 2.5 Flash only — no new AI endpoints
- Every new view uses DesignSystem tokens
- Commit after each phase passes verify