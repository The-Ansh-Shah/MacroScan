# MacroScan — Build Instructions (Iteration 4)

Reference: [ARCHITECTURE.md](ARCHITECTURE.md), [PROGRESS.md](PROGRESS.md), prior INSTRUCTIONS-V2 / V3

This iteration completes the body composition + goal planning experience that was scaffolded in Phase 12 and partially audited in Phase 15. It adds:

1. **Me tab** — dedicated TabView entry consolidating measurements, body comp, and goal planning
2. **Navy Method body fat estimation** with manual override
3. **Unified MeasurementsEditor** — one place to update all the inputs that drive computations
4. **"Meet Your Goal" flow** — desired body fat + timeframe → activity / calorie / macro targets
5. **Activity targets** (Tier 1: steps + training frequency only — no workout programming)
6. **Goal-aware Today targets** — when an active goal exists, Today reflects its targets
7. **Pre-goal measurement check** — setting a goal asks if measurements need updating first

Read the entire document. Update `PROGRESS.md` as items complete.

---

## Important context

This iteration assumes Phase 15 (measurement-flow audit) and Phase 18 (Apple Health) are **complete**. If Phase 18 is not complete, the step-tracking parts of activity targets will require manual entry — note in implementation but don't block on it.

Phases 12 and 15 already created the foundation: `BodyMeasurement`, `WeightGoal`, `BodyCompositionService`, `GoalPlannerView`, `GoalProgressView`, hard safety rails (calorie floor, weekly loss cap, protein floor, body fat floor, minimum timeline). Most of this iteration is **completing existing scaffolding**, not new construction. Audit what exists before rebuilding.

---

## Phase 22 — Body Fat Estimation (Navy Method)

### Why
Phase 12 stores `bodyFatPct` as a manual input on `BodyMeasurement`, but doesn't help users get that number. The Navy Method is the standard at-home formula: needs only waist, neck, height (and hip for women). ~3% accuracy vs. DEXA, no equipment.

### Data model

`BodyMeasurement` already has `waistIn`. Add what's missing:

```swift
@Model
final class BodyMeasurement {
    // ... existing fields ...
    var neckIn: Double?
    var hipIn: Double?              // required for women's formula only
    var bodyFatSource: BodyFatSource?
}

enum BodyFatSource: String, Codable {
    case navy           // computed from circumferences
    case manual         // user entered (calipers, scale, etc.)
    case healthkit      // synced from Health
}
```

Light migration; existing rows have `nil` neck/hip and `nil` source.

### Service

Extend `BodyCompositionService`:

```swift
enum BodyFatEstimationError: Error {
    case missingMeasurement(field: String)
    case invalidMeasurement(field: String)
    case sexNotSpecified
}

struct BodyFatEstimate {
    let pct: Double
    let source: BodyFatSource
    let confidence: Confidence  // .high (Navy w/ all inputs) / .medium (manual) / .low
}

extension BodyCompositionService {
    /// US Navy Method body fat % from circumference measurements.
    /// Men:   86.010 * log10(waist - neck) - 70.041 * log10(height) + 36.76
    /// Women: 163.205 * log10(waist + hip - neck) - 97.684 * log10(height) - 78.387
    func estimateBodyFatNavy(
        sex: BiologicalSex,
        heightIn: Double,
        waistIn: Double,
        neckIn: Double,
        hipIn: Double?
    ) throws -> BodyFatEstimate
    
    /// Convenience: pull latest measurement + profile and try Navy first, fall back to manual.
    func currentBodyFat(profile: UserProfile, latest: BodyMeasurement?) -> BodyFatEstimate?
}
```

Implementation notes:
- Use `log10` (Foundation has it). Round result to 1 decimal.
- Validate inputs: waist > neck (men) or waist + hip > neck (women), else `.invalidMeasurement`. Sane bounds: each measurement between 10 and 100 inches.
- If `BiologicalSex == .unspecified`, throw — formula requires it.

### UI integration

- In `MeasurementsEditor` (Phase 24), add neck and hip fields next to waist. Show "Navy estimate: 18.4%" inline as user types — live feedback.
- If a manual `bodyFatPct` is also entered on the same measurement save, manual wins (it's more precise) but the Navy estimate is still stored as a separate field for reference. Or: only one is set per measurement, with a small toggle "Estimate from circumferences" vs "Enter directly."
- Default behavior: if user enters waist + neck (+ hip if female) but leaves `bodyFatPct` blank, save the Navy estimate into `bodyFatPct` and `bodyFatSource = .navy`.

### Verify
- Enter realistic measurements (e.g., male, 5'10", 32" waist, 15.5" neck) → Navy estimate ≈ 13-15%
- Enter measurements that violate constraints (waist < neck) → friendly error, no save
- Toggle to manual override, enter 18% → saved as `.manual`, Navy estimate ignored

---

## Phase 23 — Me Tab

### Why
Body composition and goal planning are currently scattered across Settings → BodyComposition, Settings → GoalPlanner, etc. Per user preference, consolidate into a dedicated tab.

### Tab structure

`RootView` TabView gains a fifth tab:

```
[Today] [Dining] [History] [Me] [Settings]
```

`Me` tab icon: `person.crop.circle` (filled when selected).

### `MeView` layout

A scrollable view with sections:

1. **Header** — current weight, current body fat % (with source badge), trend arrow vs. last measurement
2. **Active goal card** (if `WeightGoal.isActive`) — target body fat / weight, days remaining, progress vs. linear projection (mini chart), "View progress" button → `GoalProgressView`
3. **Quick actions** — "Log measurement", "Update measurements", "Plan a goal" buttons
4. **Recent measurements** — last 5 measurements as a list, tap to view all → existing `BodyCompositionView` weight/BF charts (preserve)
5. **Targets summary** (read-only) — current calorie + protein + step targets, with a note: "Driven by active goal" or "Manual settings"

The existing `BodyCompositionView` charts and history list become the destination of "View all measurements." Don't rebuild — just route to it.

The existing `GoalPlannerView` becomes the destination of "Plan a goal" — but with the pre-flight check from Phase 25.

### Verify
- Me tab appears, mounts cleanly, shows real data from existing measurements
- All quick actions route to the right destinations
- Active goal card appears only when a goal is active

---

## Phase 24 — Unified MeasurementsEditor

### Why
Currently: weight is logged in `BodyCompositionView`, height/age/sex/activity are in Settings. User wants one place.

### View

`MeasurementsEditor` — presented as a sheet from "Update measurements" button on `MeView`.

Sections (use `Form` with grouped sections):

**Body** (one-time-ish, change rarely)
- Height (in or cm picker)
- Age
- Biological sex (segmented: male / female / unspecified)
- Activity level (picker with descriptions: sedentary / lightly / moderately / very / extremely)

**Today's measurement** (creates a new `BodyMeasurement` on save)
- Weight (lb / kg picker)
- Waist (in / cm)
- Neck (in / cm)
- Hip (in / cm) — visible only if sex == female
- Body fat % — manual, optional. Below it shows live Navy estimate if circumferences are filled in: "Estimate from measurements: 14.2% (Navy Method)"
- Optional notes

**Save behavior:**
- "Body" section updates `UserProfile` (in place)
- "Today's measurement" section creates a new `BodyMeasurement` with `recordedAt = Date()`
- If user only changes Body fields and leaves measurement section blank → only profile updates, no new BodyMeasurement
- If user fills in measurement fields → new `BodyMeasurement` saved, with body fat populated from manual input OR Navy estimate

### Reusing existing surfaces

The standalone "Log Measurement" button on `MeView` should also use this view (or a slimmed variant showing only the measurement section). Don't create two competing forms.

### Verify
- Open editor, change height → profile updates, no duplicate BodyMeasurement created
- Enter weight + waist + neck → BodyMeasurement saved with Navy-derived body fat
- Enter weight + manual bodyFatPct → saved with manual source, Navy ignored
- Body fields and Today's Measurement save in one tap, both reflected on Me tab

---

## Phase 25 — Meet Your Goal Flow

### Why
The existing `GoalPlannerView` accepts a target weight or body fat + date and outputs calorie + protein targets. Extend it to also output **activity targets** (steps + training frequency) and add a measurement-update prompt before planning.

### Pre-flight measurement check

When user taps "Plan a goal" on MeView:

1. Check freshness of latest `BodyMeasurement`. If older than 7 days, OR profile is missing height/age/sex/activity, show a sheet:
   > "Your most recent measurement is from [12 days ago]. Updating it gives you a more accurate plan. Update now?"
   >
   > [Update measurements] [Use existing data] [Cancel]
2. "Update measurements" routes to `MeasurementsEditor` → on save, returns to the goal flow
3. "Use existing data" proceeds directly to planner

Skip the prompt if measurement is fresh (< 7 days) AND profile is complete.

### Updated `GoalPlannerView` inputs

Existing inputs (target weight or body fat, target date) stay. Add:

- **Goal type segmented control:** target weight / target body fat (already exists, ensure it works)
- **Target date** (existing)
- **Plan basis** (read-only display) — shows the inputs being used: "Based on 168.4 lb, 14.2% body fat (Navy), 5'10", 20yo male, moderate activity"

### Output additions — activity targets

`BodyCompositionService.computeDeficitPlan` returns `DeficitPlan` (calorie + protein + warnings). Extend it:

```swift
struct DeficitPlan {
    // ... existing fields ...
    var dailyStepTarget: Int           // new
    var trainingFrequencyPerWeek: Int  // new (3-5 typical)
    var trainingNote: String           // new (e.g., "45-60 min sessions, prioritize compound lifts")
}
```

Logic:
- **Step target:** scale from current activity level baseline. Sedentary → 7,500, lightly active → 8,500, moderately active → 10,000, very active → 12,000. Cap at 12,500.
- **Training frequency:** if active goal exists, recommend 3-5 sessions/week (4 default). For aggressive cuts (>20% deficit), lean toward 3 to support recovery. For maintenance/recomp, 4-5.
- **Training note:** static text based on the case. Don't get fancy. Examples:
  - Cut: "3-4 strength sessions per week, 45-60 min, focus on compound lifts to preserve muscle. Add 1-2 light cardio days for recovery."
  - Maintain: "4-5 strength sessions per week, 60 min, progressive overload."
  - Bulk: "4-5 strength sessions per week, 60-75 min, focus on adding weight or reps each session."

This is **not** a workout programmer. It's a one-paragraph recommendation. Hevy or any other lifting app handles the actual logging. Make this clear in the UI: "For workout tracking, use a dedicated app like Hevy. This is just a target."

### Display

`GoalPlannerView` result section, after the existing macro plan, adds:

```
Activity Targets
─────────────────────
Daily Steps             10,000
Training Sessions       4 / week
Approach                45-60 min compound lifts, 1-2 light cardio days
```

### Safety rails (no change to existing, but verify all 5 still trigger)

The existing safety system already covers what was asked:
1. Calorie floor (1500 men / 1200 women)
2. Weekly loss cap (1% bodyweight/week)
3. Protein floor (0.7g/lb)
4. Body fat floor (10% men / 18% women)
5. Min timeline (deficit > 25% TDEE)

Per user preference (option A from earlier discussion): if the goal's required deficit breaches body fat floor or any other critical rail, the existing **hard-block-with-override** behavior is correct. Verify it still works:
- Critical warning banner shown
- "Apply" button replaced with "I understand the risks — apply anyway"
- Tapping it requires explicit confirmation alert before proceeding
- Plan is marked `isSafe = false` and the active goal carries that flag

### Verify
- Plan a reasonable goal (lose 8 lb over 12 weeks) → all targets generated, safe, no critical warnings
- Plan an unsafe goal (lose 15 lb in 14 days) → critical banner, override-only path, applied goal marked unsafe
- Pre-flight check fires when measurement is stale; skips when fresh
- Activity targets appear with clear "use Hevy for actual workout logging" note

---

## Phase 26 — Goal-Aware Today Targets

### Why
User explicitly wants: "if a goal is set and a timeframe is given, the today page's targets should be updated based on the goals."

### Behavior

When applying a goal in `GoalPlannerView`:
1. Set `WeightGoal.isActive = true` (deactivating any prior active goals)
2. Write `dailyCalorieTarget`, `dailyProteinTargetG`, `dailyStepTarget` from the plan into `UserProfile`
3. Carb and fat targets recompute to fill the remaining macro budget (existing logic, verify)
4. Today's `MacroRingsView` and `MicroBarsView` immediately reflect new targets — they read from `UserProfile`, so this should "just work" if reactivity is correct

Steps target: new field on `UserProfile`:

```swift
extension UserProfile {
    var dailyStepTarget: Int   // default 8000 if no active goal
}
```

### Today integration

Add a **steps ring** to `MacroRingsView` (or a separate small component near it). Reads today's step count from HealthKit if available (Phase 18); shows "—" if HealthKit is denied or unavailable. Tappable → opens Apple Health.

Don't auto-add active energy to the calorie budget. Existing rule from Phase 18 still applies: surface activity, don't credit it.

### Visual cue when targets are goal-driven

On Today, near the macro rings, a small subtle label: "Targets: Cut to 14% by Aug 15" (or whatever the active goal is), tappable → MeView. When no active goal, show: "Targets: Manual" or hide entirely.

### Verify
- Apply a goal → Today's calorie/protein targets immediately reflect new values
- Steps ring shows real data (if Phase 18 done)
- Goal label shows correctly; tapping routes to MeView
- Deactivating a goal in MeView → Today reverts to manually-set or default targets

---

## Phase 27 — Logging Weight Doesn't Reset the Goal

### Why
User explicit preference: "logging weight doesn't update the time frame every single time."

This is supposed to be the existing behavior from Phase 12, but verify and lock it down.

### Rules to enforce

1. **Logging a new weight** (creating a `BodyMeasurement`) updates:
   - Latest weight displayed everywhere
   - `GoalProgressView` chart (new data point added to actual-vs-projection)
   - Any computed BMR/TDEE *displays* (not the targets themselves)
2. **Logging a new weight does NOT update:**
   - `WeightGoal.targetDate`
   - `WeightGoal.targetWeightLb` / `targetBodyFatPct`
   - `UserProfile.dailyCalorieTarget` / `dailyProteinTargetG`
3. **Updating the goal itself** is the only way targets change. That's a deliberate user action via `GoalPlannerView`.

If user wants to recompute targets based on new weight (e.g., 6 weeks in, lost 5 lb, want to recalculate): they explicitly open GoalPlanner and re-apply. A small button on Active Goal card: "Recompute targets based on current weight" — opens GoalPlanner pre-filled.

### Verify
- Active goal in place. Log a new weight. Confirm: Today targets unchanged, GoalProgressView updates, displayed BMR/TDEE updates if relevant
- "Recompute targets" button available on active goal — pre-fills planner, user must explicitly re-apply

---

## Progress updates

Append to `PROGRESS.md`:

```markdown
# Iteration 4

## Phase 22 — Navy Method Body Fat Estimation
- [ ] BodyMeasurement: neckIn, hipIn, bodyFatSource fields
- [ ] BodyFatSource enum
- [ ] BodyCompositionService.estimateBodyFatNavy
- [ ] BodyCompositionService.currentBodyFat convenience
- [ ] Validation: waist > neck (men) or waist + hip > neck (women)
- [ ] **Verify:** realistic inputs → reasonable estimate; invalid inputs → friendly error

## Phase 23 — Me Tab
- [ ] RootView TabView gains Me tab
- [ ] MeView with header / active goal card / quick actions / recent measurements / targets summary
- [ ] Routes to existing BodyCompositionView, GoalPlannerView, GoalProgressView preserved
- [ ] **Verify:** tab appears, all routes work, real data renders

## Phase 24 — Unified MeasurementsEditor
- [ ] MeasurementsEditor sheet with Body + Today's Measurement sections
- [ ] Live Navy estimate preview as circumferences typed
- [ ] Sex-conditional hip field
- [ ] Single save updates UserProfile and creates BodyMeasurement appropriately
- [ ] Replaces (or unifies with) any existing scattered measurement entry surfaces
- [ ] **Verify:** body fields update profile only; measurement fields create new BodyMeasurement; both can save together

## Phase 25 — Meet Your Goal Flow
- [ ] Pre-flight measurement check (>7 days old triggers prompt)
- [ ] DeficitPlan extended: dailyStepTarget, trainingFrequencyPerWeek, trainingNote
- [ ] Step target derived from activity level baseline
- [ ] Training frequency + note from goal type and deficit size
- [ ] GoalPlannerView shows Activity Targets section with "use Hevy" note
- [ ] All 5 safety rails still trigger correctly
- [ ] Hard-block-with-override path requires explicit confirmation
- [ ] Plan basis (inputs being used) clearly shown
- [ ] **Verify:** safe goal generates full plan; unsafe goal triggers override flow; plan basis transparent

## Phase 26 — Goal-Aware Today Targets
- [ ] UserProfile.dailyStepTarget field
- [ ] Applying a goal writes calorie + protein + step targets to UserProfile
- [ ] Today's macro rings immediately reflect new targets
- [ ] Steps ring on Today (HealthKit data if Phase 18 done; "—" otherwise)
- [ ] "Targets: <goal summary>" label on Today, tappable → MeView
- [ ] Deactivating goal reverts targets correctly
- [ ] **Verify:** apply a goal → Today shows new targets; deactivate → Today reverts

## Phase 27 — Goal Stickiness
- [ ] Audit: logging weight does NOT modify WeightGoal or UserProfile targets
- [ ] GoalProgressView updates with new weight points
- [ ] BMR/TDEE displays update with new weight (displays only, not targets)
- [ ] "Recompute targets based on current weight" button on active goal card → opens pre-filled GoalPlanner
- [ ] **Verify:** logging weight while goal active leaves targets stable; recompute button works
```

---

## Build Order

1. **Phase 22** (Navy estimation) — foundational; everything downstream uses it
2. **Phase 24** (MeasurementsEditor) — needed before Me tab is useful
3. **Phase 23** (Me tab) — consolidation; safe to ship independently
4. **Phase 27** (Goal stickiness audit) — small, but want to verify before adding more goal logic
5. **Phase 25** (Meet Your Goal extensions) — biggest phase; depends on 22 + 24
6. **Phase 26** (Today targets reflection) — closes the loop; depends on 25

Estimated total: 8-12 hours, mostly UX and wiring.

## Constraints

- Follow `ARCHITECTURE.md` §15 conventions
- No new external Swift packages
- No new AI integrations
- Every new view uses DesignSystem tokens
- Commit after each phase passes verify
- Activity targets are recommendations, not workout programming. The training note must mention Hevy or "your preferred lifting app" — do not pretend MacroScan is a training tracker.
- Safety rails from Phase 12 must continue to function. If audit reveals they don't, fix before Phase 25.
- Goal-planning surfaces continue to display the existing `GoalPlanning.disclaimer` footer (Phase 12).