# MacroScan — Build Instructions (Iteration 5)

Reference: [ARCHITECTURE.md](ARCHITECTURE.md), [PROGRESS.md](PROGRESS.md), prior iterations V2–V4

This iteration is a **consolidation pass**. It removes what isn't working, fixes what's stale, and rounds out features the user finds missing in daily use.

Changes:

1. **Remove dining hall integration entirely** (clean delete)
2. **Reorganize Settings** — remove redundant target editors, move micros to Me page, use standard RDI defaults when no active goal
3. **Target body fat as a goal option** — GoalPlannerView gains a Weight / Body Fat segmented control
4. **Water tracking** with HealthKit sync
5. **Servings-or-grams logging** — either unit accepted anywhere gramsEaten is currently required
6. **Remove vegetarian toggle from log-food surfaces** — it's a profile preference, not a per-log decision
7. **Steps diagnostic + fix** — figure out why step targets aren't updating and fix the actual failure
8. **Cosmetic: calorie display rounding** — "1,768.89…" should be "1,768"

Read the entire document. Update `PROGRESS.md` as items complete.

---

## Phase 28 — Remove Dining Hall Integration

### Why
The user has decided the dining hall feature isn't delivering value and wants it gone. Cal Dining scraper was never finalized, the optimizer was running on placeholder data, and keeping unused code creates cognitive load. Delete it cleanly.

### What to delete

Files:
- `Models/DiningMenu.swift` (and any sub-models like `DiningMenuItem` if they exist as separate files)
- `Services/DiningMenuService.swift`
- `Services/DiningOptimizer.swift`
- `Views/Dining/` (entire directory — DiningView, OptimizerView, OptimizerResultView, any others)

Code references to remove:
- `DiningLocation` enum (if it exists)
- `.diningHall` case from `FoodSource` enum (and update any exhaustive switches)
- `Food.diningLocation` field
- `diningMenus` / `WeightGoal.dining` relationships or fields if any
- `ModelContainer` registration of dining models
- Dining tab from `RootView` TabView
- Any dining-related entries in `DayView` "+ Add" menu

### Data migration

Drop the SwiftData tables for `DiningMenu` (and related) by removing them from the `ModelContainer` schema. SwiftData will handle removal on next launch. Users (the user) will lose any cached menu data, which is fine — it was placeholder.

Any existing `LogEntry` rows where `food.source == .diningHall` should migrate to `.manual` before the enum case is removed. Script this as part of the migration:

```swift
// One-time migration inside the app launch flow
let container = try ModelContainer(...)
let context = ModelContext(container)
let affected = try context.fetch(FetchDescriptor<Food>(
    predicate: #Predicate { $0.sourceRaw == "diningHall" }
))
for food in affected {
    food.sourceRaw = "manual"
}
try context.save()
```

(Exact field name depends on how the enum is currently persisted — adapt to actual codebase.)

### TabView adjustment

`RootView` tabs become: **Today / History / Me / Settings** (four, not five). Confirm ordering still makes sense.

### Verify
- `grep -ri "dining" Views/ Services/ Models/` returns zero hits (outside of comments referencing the removal)
- App builds clean
- No orphaned LogEntries crash the app
- Four tabs render correctly

---

## Phase 29 — Settings Reorganization

### Why
After Phase 26, Settings' Diet Goal and Macro Targets sections became vestigial. Goal-driven targets overwrite manual ones, creating a confusing dual-source-of-truth. Simplify.

### Remove from Settings

- **Diet Goal** segmented control (Cut/Maintain/Bulk)
- **Macro Targets** section (calorie, protein, carbs, fat editors)
- **Micro Targets** section (fiber, iron, vitamin D, B12 editors)

`UserProfile.dietGoal` stays in the model (used elsewhere, including goal planning context) but is no longer user-editable from Settings. It's set implicitly when applying a goal.

### Move Micro Targets to Me tab

Add a **"Micronutrient Targets"** section to `MeView`, below the existing sections. Editable. These are not goal-driven in our current logic — they're RDI-based static targets the user can customize (e.g., if they're tracking higher iron for vegetarian reasons, already set to 18mg by default).

### Default micros when no active goal

Confirm defaults match standard adult RDIs:
- Fiber: 30g (was already this)
- Iron: 18mg (vegetarian-adjusted default — keep)
- Vitamin D: 15mcg (600 IU) — instructions had 20mcg earlier; 15mcg matches US RDA for adults 19-70
- Vitamin B12: 2.4mcg

No change if already set. Just verify.

### What Settings should still contain

After removal, Settings should have:
- Apple Health section (Phase 18)
- AI Usage section (Phase 14)
- Exclusions / Dietary Preferences (keep)
- Auto-set protein from weight toggle (keep, but only works when no active goal)
- About / Credits (FatSecret attribution, etc.)

### Verify
- Settings is now short and clearly about app-wide preferences, not targets
- Micro targets appear on Me tab, editable
- Removing a goal (if active) reverts calorie + protein to sensible manual-override defaults
- No crash when a prior install had manual targets — migrate gracefully

---

## Phase 30 — Target Body Fat in Goal Planner

### Why
User explicitly asked for this and assumed it was already built. Phase 12 architecture specified `WeightGoal.targetBodyFatPct` as optional but the UI only surfaces target weight. Complete it.

### UI changes

`GoalPlannerView` gains a segmented control at the top:
- **Target Weight** (default)
- **Target Body Fat**

Based on selection, show:
- Target Weight: numeric input in lb/kg
- Target Body Fat: numeric input in %

Target date picker unchanged, applies to both.

### Plan computation

`BodyCompositionService.computeDeficitPlan` needs a body-fat path. Given current weight, current body fat %, target body fat %, target date:

1. Compute current lean body mass: `currentLBM = currentWeight * (1 - currentBodyFatPct / 100)`
2. Assume LBM stays roughly constant (it shifts some — with adequate protein + training, loss is mostly fat)
3. Compute target weight at target BF%: `targetWeight = currentLBM / (1 - targetBodyFatPct / 100)`
4. From there, delegate to existing target-weight deficit logic

If `currentBodyFatPct` is nil (user hasn't logged a measurement with BF%):
- Surface a warning at the top of the planner: "Body fat goals require a current body fat measurement. Update measurements first."
- Disable the "Target Body Fat" option with a tooltip, OR route to `MeasurementsEditor` first
- This ties into Phase 25's pre-flight check — extend it: if target type is body fat and no current BF%, prompt before anything else

### Additional safety rail

Body fat floor (Phase 12): reject or warn-critical on targets below 10% (men) / 18% (women). This already exists — confirm it triggers when the goal type is body-fat-based, not just when derived from weight.

### Verify
- Toggle to "Target Body Fat", enter 14% with a reasonable date → plan generates, targets applied correctly
- Enter 8% for a male profile → critical warning banner, override-required flow
- With no current BF% measurement, body fat option prompts for measurement first

---

## Phase 31 — Water Tracking

### Why
Standard feature, user asked, HealthKit supports it natively. Low effort given Phase 18 groundwork.

### Data model

New `@Model`:

```swift
@Model
final class WaterEntry {
    var recordedAt: Date
    var amountMl: Double          // stored in ml internally; display converts
    var source: String            // "manual" | "healthkit"
}
```

Add to `UserProfile`:

```swift
var dailyWaterTargetMl: Double    // default 2750 (roughly 3/4 gallon); editable
```

Register `WaterEntry` in the `ModelContainer`.

### Service

Extend `HealthKitService`:

```swift
func writeWater(_ entry: WaterEntry) async throws
func waterSamples(forDate: Date) async throws -> [(ml: Double, recordedAt: Date, source: String)]
```

Uses `HKQuantityTypeIdentifier.dietaryWater`. Add to authorization request.

### Repository

Extend `FoodRepository`:

```swift
func logWater(ml: Double, at: Date = Date()) throws -> WaterEntry
func waterEntries(forDate: Date) -> [WaterEntry]
func totalWater(forDate: Date) -> Double  // ml
func deleteWater(_ entry: WaterEntry) throws
```

After each `logWater`, call `HealthKitService.writeWater` silently (Phase 18 pattern).

On a date view, if `latest HealthKit water samples > latest local samples`, surface import: "3 water entries from Health today — Import?"

### UI

**`WaterRing` or `WaterBar` component** — a new visual on `DayView` adjacent to the macro rings. Shows total oz/ml vs. target. Functional color: gray under 70%, orange 70-100%, green at/over target.

**Quick-add buttons** below the ring/bar:
- `+ 8 oz` (≈ 240 ml)
- `+ 16 oz` (≈ 470 ml)
- `+ Custom` (opens sheet with a slider or numeric input)

**Tap the ring** to open a sheet showing today's water entries, delete swipe, manual add button.

### Units

Store in ml internally. Display in oz for US locale, ml otherwise. Add a unit preference toggle in Settings (or use system locale default).

### Verify
- Tap +8oz five times → ring fills to ~40 oz / ~1200 ml
- Entries appear in Apple Health under Water
- Delete an entry, total updates, Health entry also removed (or ignore for v1 if HealthKit delete is annoying)

---

## Phase 32 — Servings-or-Grams Logging

### Why
Asking for grams is precise but cognitively heavy when a nutrition label already says "1 serving = 45g." User wants to enter "0.5 servings" or "2 servings" directly.

### Data model

`LogEntry` gains:

```swift
@Model
final class LogEntry {
    // ... existing fields ...
    var servingsEaten: Double?    // populated when logged by serving count
    // gramsEaten stays; either one is canonical, the other derived
}
```

Computation rule: on save, if `servingsEaten` is set, compute `gramsEaten = servingsEaten * food.servingSizeGrams`. Always keep both in sync for macro math.

### `Food` needs serving size awareness

Confirm `Food.servingSizeGrams` exists and is populated from all sources:
- Open Food Facts: has `serving_size` (often as a string like "30 g"), parse out the grams
- FatSecret: includes serving info in detail responses — store it
- Manual entry / AI vision: user specifies

If a Food has `servingSizeGrams = nil` or 0, the "servings" input path is hidden; only grams available. Display a subtle note: "This food doesn't have serving size data — enter grams."

### UI — log sheets

Everywhere "amount eaten" is entered (`ScanResultSheet`, `ManualFoodForm`, `EditLogEntrySheet`, search/recipe log flows):

- Segmented control at top of the amount input: **Servings / Grams**
- Default selection based on Food: if `servingSizeGrams` is populated, default to Servings. Otherwise Grams.
- Below, a single numeric input that represents whichever unit is selected
- Below that, a read-only line showing the other unit: "= 90 g" when in Servings mode; "= 2.0 servings" when in Grams mode

Numeric input accepts fractional values for servings (0.5, 1.5, 2.25).

### Display in meal sections

`FoodRow` / meal display should show whichever the user originally entered:
- Logged as 1.5 servings → "1.5 servings (67 g)"
- Logged as 80 g → "80 g (1.8 servings)" if serving size known, or just "80 g"

### Verify
- Log 1.5 servings of a barcoded item with serving size 30g → gramsEaten = 45, macros scale correctly
- Edit the entry, change to grams input, enter 60 → servings shows 2.0, macros recompute
- Food without serving size forces grams-only input

---

## Phase 33 — Remove Vegetarian Toggle from Log Surfaces

### Why
Vegetarian status is a profile-level preference (set in Dietary Preferences). It doesn't make sense to toggle per-log — you don't decide a food is vegetarian when you're eating it, the food either is or isn't.

### Changes

- Remove the vegetarian toggle/checkbox/badge from `ManualFoodForm`
- Remove from `ScanResultSheet` and search result log sheets
- Remove from `AIEstimateSheet`
- Keep `Food.isVegetarian` as a data field — it's auto-detected from ingredients or source, used for exclusion warnings and AI prompt context

If the current UI allows user override of the auto-detected vegetarian flag, move that into a less prominent place (e.g., a disclosure "Override ingredient flags" in the log sheet's advanced section) or remove it entirely. The system should detect this, not ask every time.

### Verify
- Logging a food doesn't show vegetarian toggle
- Auto-detection still tags Foods correctly
- Exclusion warnings still fire when a non-vegetarian food is logged by a vegetarian user

---

## Phase 34 — Steps Target Diagnostic

### Why
User reports step counts aren't updating. Unclear whether this is:
- Phase 18 (HealthKit) not actually wired for steps
- Phase 26 not reading the target correctly
- A display bug
- HealthKit not authorized for step reads

Diagnose before "fixing."

### Audit checklist

Write findings inline as you go. Don't change code until the root cause is clear.

1. **`UserProfile.dailyStepTarget`** — does it get written when `GoalPlannerView.applyPlan` runs? Confirm.
2. **HealthKit step reads** — is there an actual call to `HKQuantityTypeIdentifier.stepCount` anywhere? If not, steps are never read, so the display is always stale/zero/nil.
3. **Authorization** — is step read type in the `HealthKitService.requestAuthorization` set? If user was prompted only for weight + active energy, steps were never authorized.
4. **DayView steps ring** — where does it source the current step count? Local fake, HealthKit, or nothing?
5. **Reactivity** — does the steps ring re-query on view appear? On foreground re-entry?

### Likely fixes

Once root cause is known, the fix is usually one of:

- Add step count to HealthKit authorization request
- Add `latestSteps(forDate:)` method to HealthKitService
- Wire DayView steps ring to call it on appear
- Ensure target is written correctly in goal apply flow

### Verify
After fix: open app fresh in the morning → steps show 0-ish. Take a walk, come back → steps updated. With goal active, target matches what was set.

---

## Phase 35 — Cosmetic & Small Polish

### Bundled minor fixes

- **Calorie display rounding.** Settings and anywhere else showing calories: round to integer for display. "1,768.89…" → "1,768". Storage can stay Double; only format the display.
- **Vegetarian default.** First-launch profile setup: the default for `isVegetarian` is currently true. Confirm that matches user intent (Ansh is vegetarian per memory), and that it's editable in Dietary Preferences.
- **Water reminder (optional).** If the user wants, add an opt-in notification in Settings: "Remind me to drink water every 2 hours from 9am to 9pm." Simple, standard UNUserNotificationCenter. Skip if user doesn't want it.

### Verify
Visual check of calorie displays throughout the app.

---

## Progress updates

Append to `PROGRESS.md`:

```markdown
# Iteration 5

## Phase 28 — Remove Dining Hall
- [ ] Delete Models/DiningMenu.swift and any sub-models
- [ ] Delete Services/DiningMenuService.swift, DiningOptimizer.swift
- [ ] Delete Views/Dining/ directory
- [ ] Remove .diningHall from FoodSource; migrate existing Food rows to .manual
- [ ] Remove DiningLocation enum if exists
- [ ] Remove Food.diningLocation field
- [ ] Remove Dining tab from RootView
- [ ] Remove dining entries from DayView "+ Add" menu
- [ ] Update ModelContainer schema
- [ ] **Verify:** zero dining references remain; app builds; tabs render

## Phase 29 — Settings Reorganization
- [ ] Remove Diet Goal segmented control from Settings
- [ ] Remove Macro Targets section from Settings
- [ ] Remove Micro Targets section from Settings
- [ ] Add Micronutrient Targets section to MeView (editable)
- [ ] Default micros fall back to adult RDI when no active goal
- [ ] **Verify:** Settings shows only app-level prefs; micros editable on Me tab

## Phase 30 — Target Body Fat Goals
- [ ] GoalPlannerView Weight / Body Fat segmented control
- [ ] BodyCompositionService body-fat-path plan logic (LBM-preserving target weight)
- [ ] Pre-flight prompt if no current BF% measurement
- [ ] Body fat floor safety rail triggers for body-fat-typed goals
- [ ] **Verify:** body fat goals generate valid plans; unsafe targets hard-block-with-override

## Phase 31 — Water Tracking
- [ ] WaterEntry @Model + UserProfile.dailyWaterTargetMl
- [ ] HealthKitService.writeWater + waterSamples
- [ ] Water in authorization request
- [ ] FoodRepository.logWater / waterEntries / totalWater / deleteWater
- [ ] Water ring/bar on DayView
- [ ] Quick-add buttons (+8oz, +16oz, +custom)
- [ ] Tap ring → sheet with day's entries, delete, manual add
- [ ] ml/oz unit preference
- [ ] **Verify:** logging water updates ring + Health app

## Phase 32 — Servings-or-Grams Logging
- [ ] LogEntry.servingsEaten field
- [ ] Serving-size population from OFF + FatSecret sources
- [ ] Segmented control (Servings / Grams) in all log sheets
- [ ] Default to Servings when Food has servingSizeGrams, else Grams
- [ ] Read-only "= X units" display for the other unit
- [ ] FoodRow displays whichever was entered, with parenthetical
- [ ] **Verify:** log 1.5 servings scales macros correctly; edit to grams flips unit

## Phase 33 — Remove Vegetarian Toggle
- [ ] Remove from ManualFoodForm, ScanResultSheet, AIEstimateSheet, search log sheets
- [ ] Food.isVegetarian auto-detection preserved
- [ ] Exclusion warnings still fire correctly
- [ ] **Verify:** no per-log vegetarian toggle; auto-detection still works

## Phase 34 — Steps Target Diagnostic
- [ ] Audit: UserProfile.dailyStepTarget write path
- [ ] Audit: HealthKit step type in authorization request
- [ ] Audit: latestSteps query method exists
- [ ] Audit: DayView steps ring source + reactivity
- [ ] Fix the identified break
- [ ] **Verify:** step count updates; target reflects goal

## Phase 35 — Cosmetic Polish
- [ ] Calorie display rounding (integer formatting)
- [ ] Vegetarian default confirmed as true on first launch
- [ ] (Optional) Water reminders — opt-in only
- [ ] **Verify:** no decimals in calorie display; defaults sensible
```

---

## Build Order

1. **Phase 34** first — steps diagnostic. Quick win if it's a small issue; if it's a deep integration problem, knowing that up front helps scope other phases (like water) correctly since they share HealthKit code paths.
2. **Phase 28** — dining removal. Do this early because it deletes code other phases might otherwise try to update.
3. **Phase 29** — Settings reorganization. Small.
4. **Phase 33** — remove vegetarian toggle. Small.
5. **Phase 35** — cosmetic polish. Small.
6. **Phase 32** — servings/grams. Touches a lot of log surfaces, but each touch is small.
7. **Phase 30** — body fat goals. Medium; builds on existing planner.
8. **Phase 31** — water tracking. Largest single phase; new model + service + UI.

Estimated total: 8-10 hours.

## Constraints

- Follow `ARCHITECTURE.md` §15 conventions
- No new external packages
- No new AI integrations
- Every new view uses DesignSystem tokens
- Commit after each phase passes verify
- When removing code, commit the deletion separately from any additions — easier to review/revert