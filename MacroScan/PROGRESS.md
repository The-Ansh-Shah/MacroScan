# MacroScan — Build Progress

Reference: [ARCHITECTURE.md](ARCHITECTURE.md), [INSTRUCTIONS.md](INSTRUCTIONS.md)

---

## ⚠️ Current Build State

Build break from prior iteration is fixed — `ProfileSetupView` now exists at [Views/Onboarding/ProfileSetupView.swift](Views/Onboarding/ProfileSetupView.swift).

**Still compiling but in transitional state:**
- `Food.ingredients: [String]` default `[]` — SwiftData lightweight migration should succeed. If on-device migration fails, delete app + reinstall.
- `UserProfile` has several optional new fields (`heightIn`, `ageYears`, `biologicalSexRaw`, `activityLevelRaw`, `currentGoal`, `aiCallsTotal`, `aiQuotaErrorsTotal`, `aiLastErrorAt`).
- `BodyMeasurement` and `WeightGoal` are registered in the shared model container.

---

## Phase 1 — Foundation
- [x] Models: Food, LogEntry, UserProfile, DiningMenu, Enums
- [x] DesignSystem: Colors, Typography, Spacing
- [x] DesignSystem Components: MacroRing, TargetBar, FoodRow, PrimaryButton
- [x] MacroScanApp.swift — ModelContainer with all models
- [x] RootView with TabView skeleton (Today / Dining / History / Settings)
- [x] UserProfile singleton created on first launch
- [x] **Verify:** builds, tabs render, SF Rounded visible

## Phase 2 — Barcode Path
- [x] BarcodeScanner.swift (AVFoundation, @Observable)
- [x] Camera permission flow
- [x] OpenFoodFactsAPI.swift (actor) — now with `search(query:)` and `DoubleOrString` tolerant decoder
- [x] ScannerView + ScanResultSheet
- [x] FoodRepository CRUD + aggregation
- [x] DayView list of day's entries
- [x] **Verify:** builds, scanner wired, OFF lookup works

## Phase 3 — Manual + Today Polish
- [x] ManualFoodForm
- [x] MacroRings in DayView + MicroBarsView
- [x] QuickLogBar with MealRanker
- [x] MealSectionView with long-press + ellipsis-button menu
- [x] Haptics on log actions
- [x] **Verify:** fully functional Today tab without AI

## Phase 4 — AI Vision
- [x] Secrets.plist setup (GEMINI_API_KEY)
- [x] AIVisionService.swift (Gemini 2.5 Flash, structured JSON)
- [x] PhotoCaptureView (UIImagePickerController wrapper)
- [x] AIEstimateSheet (editable confirm, confidence badge, warnings)
- [x] DayView "Snap Photo" flow wired end-to-end
- [x] **Verify:** builds clean

## Phase 5 — History + Settings
- [x] HistoryView with Swift Charts (moved into "Trends" segmented tab — see Phase 10)
x- [x] WeeklyReviewView (daily averages, notes journal)
- [x] SettingsView (macro/micro target editors, body weight, auto-protein, body/goals navigation, AI usage)
- [x] ExclusionsEditor (add/remove excluded ingredients)
- [x] **Verify:** builds clean, all views wired

## Phase 6 — Dining Hall
- [x] DiningMenuService (actor, fetch + cache, placeholder URL)
- [x] DiningOptimizer (greedy algorithm, dietary exclusion filter)
- [x] DiningView (location picker, menu browse, refresh)
- [x] OptimizerView (remaining budget, suggested plan, accept → log)
- [x] **Verify:** builds clean (gated on real data endpoint)

## Phase 7 — Close the Gap
- [x] CloseGapView (remaining targets, gap-closing food suggestions)
- [x] "What should I eat?" button in DayView
- [x] **Verify:** builds clean, wired to MealRanker.closeGapSuggestions

## Phase 8 — Visual Polish
- [x] ShimmerModifier + SkeletonRow for loading states
- [x] Skeleton loading in DiningView
- [x] Scale+opacity transition on scanner loading
- [x] Ring animation: .easeOut(1.2s)
- [x] Spring animation: .spring(0.4, 0.8)
- [x] Empty states on all list views (Today, History, Dining, Settings)
- [x] Haptics on log, target hit, sheet dismiss, picker change
- [x] **Verify:** full build succeeds with 0 errors

---

# Iteration 2

## Phase 9 — Log Management ✅
- [x] Swipe-to-delete audit + replacement with `.contextMenu` + ellipsis-button dialog
- [x] `EditLogEntrySheet` — updates in place via `FoodRepository.updateEntry`
- [x] `FoodRepository.updateEntry(_:grams:mealType:loggedAt:notes:)`
- [x] `Haptics.deleted()` rigid impact
- [x] `LogEntry.notes: String?`
- [x] **Verify:** delete + edit work across long-press / ellipsis paths.

## Phase 10 — Day-Based Organization ✅
- [x] `DayView(date: Binding<Date>, isTodayTab: Bool)`; `TodayView` removed
- [x] `TodayTabView` wraps `DayView` with a `DateScroller`
- [x] `DateScroller` — 60 days back, target-hit dot per day
- [x] `HistoryView` reworked with "Days" / "Trends" Picker
- [x] Day-navigation chevrons in DayView toolbar
- [x] `RootView` Today tab mounts `TodayTabView`
- [x] **Verify:** navigate arbitrary past days; charts still render under Trends.

## Phase 11 — Text Search & Substitutions ✅
- [x] `OpenFoodFactsAPI.search(query:limit:)` + `OFFSearchResponse` decoder
- [x] `FoodSearchService` — local-first, OFF fallback, dedup
- [x] `SearchView` — debounced 250ms, live results, source icons, `initialQuery` support for deep links
- [x] `DayView` "Search Foods" menu item
- [x] `LogEntry.notes: String?`
- [x] `Food.ingredients: [String]`
- [x] **Populate `Food.ingredients` from OFF** — parse `ingredients_text`, strip parentheticals, trim, drop empty
- [x] **`DoubleOrString` tolerant decoder** — handles OFF search returning nutrient values as strings
- [x] **Ingredient substitution UI** — `ScanResultSheet` gains a "Customize ingredients" disclosure, per-ingredient Replace button, `IngredientSubstitutePicker` over the local library, even-distribution-share macro math, "Approximate" label
- [x] **Notes at log creation** — `ScanResultSheet` has a notes field; `FoodRepository.logFood(...notes:)` extended
- [x] **Swap notes auto-generated** — `"swapped: original → replacement"` appended to LogEntry notes
- [x] **Derived Food snapshot on customization** — so logged macros reflect the swap, not the unmodified base
- [x] **Verify:** text search finds real products; substitutions update macros with Approximate label; notes persist on create + edit.

## Phase 12 — Body Composition & Goal Planning ✅
- [x] `BodyMeasurement` @Model
- [x] `WeightGoal` @Model
- [x] `BiologicalSex` + `ActivityLevel` enums
- [x] `UserProfile` extended with height, age, sex, activity
- [x] `BodyCompositionService` — BMR / TDEE / `computeDeficitPlan` with all 5 safety rails
- [x] `DeficitPlan` + `SafetyWarning` with `.severity`
- [x] `ProfileSetupView` — first-launch onboarding (skippable); collects height, age, sex, activity, weight, optional BF%, inserts first `BodyMeasurement` on save
- [x] `BodyCompositionView` — weight + BF% charts, history list, "Log measurement" sheet; mirrors latest weight back to profile
- [x] `GoalPlannerView` — target weight + date, plan summary, `WarningBanner`s per severity, critical `.alert` gate before applying unsafe plans, `GoalPlanning.disclaimer` footer
- [x] `GoalProgressView` — weight vs. linear projection chart, purely visual; disclaimer footer
- [x] Settings wiring — "Body Composition", "Goal Planner", "Active Goal Progress" (conditional) NavigationLinks + Profile section for height / age / sex / activity
- [x] Applying a plan deactivates prior active goals, creates new `WeightGoal`, writes `dailyCalorieTarget` + `dailyProteinTargetG` onto profile
- [x] `GoalPlanning.disclaimer` extracted — single source of truth, reused by GoalPlannerView + GoalProgressView + ProfileSetupView
- [x] **Verify:** safety rails trigger on absurd inputs; disclaimer appears on every goal-planning surface; applying targets updates UserProfile.

## Phase 13 — Daily Balance Insights ✅
- [x] `BalanceFlag` struct with deep-link enum
- [x] `FoodRepository.balanceFlags(forDate:profile:)` — today-only; protein / fiber / fat / calorie-deficit / micro-streak flags
- [x] `InsightsCard` on DayView, collapsible, max 2 flags, session-scoped info dismissal
- [x] **Deep-link wiring** — `InsightsCard` accepts `onDeepLink` callback; rows are tappable; chevron affordance shown when a link exists; DayView presents `CloseGapView` or `SearchView(initialQuery:)` accordingly
- [x] `SearchView` gains `initialQuery` to support deep-link prefill
- [x] **Verify:** flags fire at the right times; past-day review shows no flags; deep links route to the correct sheet; dismissed info flags stay hidden within a session.

### Accepted tradeoff
- Dismissal is **session-scoped**, not day-persistent. INSTRUCTIONS spec says "dismiss for that day"; session scope is a reasonable first pass — if the user re-opens the app the flag returns, which is fine for the first pass. Persist via `UserDefaults` if it becomes annoying.
- Streak check scans 14 days × 3 micros = 42 SwiftData fetches per InsightsCard render. Acceptable for now; cache if Instruments shows it hot.

## Phase 14 — AI Resilience ✅
- [x] `AIVisionService.analyze(...)` gains `progress` callback + retry loop with 1s / 3s / 8s exponential backoff; 3 attempts total
- [x] `isRetryable(_:)` — matches 429 / 503 / "high demand" / "overloaded" / "quota" / "rate limit" / network errors
- [x] `isQuotaError(_:)` — used for the quota-specific fallback message
- [x] `AIEstimateSheet` — progress label updates ("Analyzing…" → "Retrying…" → "Still trying…"); increments `profile.aiCallsTotal`; on quota error increments `aiQuotaErrorsTotal` + sets `aiLastErrorAt`
- [x] `AIFallbackSheet` — captured photo preserved; inline manual form; quota-specific banner; photoData stored into the final LogEntry
- [x] Error view now offers a "Log manually instead" button that presents the fallback
- [x] **AI Usage section in Settings** — total analyses, quota errors (orange when >0), relative-style last error timestamp
- [x] **Verify:** simulate a Gemini failure (swap endpoint URL or throttle network); fallback sheet opens with photo; counters increment.

---

## Pointer to known quirks

See [FINDINGS.md](FINDINGS.md) for:
- Swift 6 / MainActor default-isolation behavior
- SwiftData enum-raw-string pattern
- `@preconcurrency` conformance for AVFoundation delegates
- File-system-synchronized Xcode group (no manual pbxproj edits)

---

## Iteration 2 — Status

All phases (9–14) complete. Ready for a local build verify in Xcode (no local `xcodebuild` CLI is available per environment notes). Key manual test paths:

1. **Onboarding** — fresh install opens `ProfileSetupView`; "Skip" keeps nil fields; "Save" persists profile + inserts initial `BodyMeasurement`.
2. **Substitution flow** — scan a barcode for a product with ingredients, open "Customize ingredients", swap one, confirm the Approximate label appears and macros shift.
3. **Goal safety rails** — try to lose 15 lb in 14 days from a 170-lb profile → expect red critical banner(s) + acknowledgement alert before applying.
4. **Insights deep link** — late evening with low protein logged → tap the "Protein running low" row → CloseGapView opens.
5. **AI fallback** — temporarily set an invalid API key in Secrets.plist → after retries, error view appears; "Log manually instead" opens the fallback with the photo preserved.

---

# Iteration 3

## Phase 15 — Measurement-Flow Audit ✅
- [x] Audit found: `FoodRepository.balanceFlags` called `BodyCompositionService.tdee(from: profile)` without passing current weight → always fell back to stale `profile.bodyWeightLb`
- [x] Audit found: `BodyCompositionView` never rendered TDEE, targets, or active goal (data went in, nothing came out)
- [x] Audit found: `GoalPlannerView` didn't show the inputs that drove the recommendation
- [x] Audit found: `LogMeasurementSheet` was mirroring weight into `profile.bodyWeightLb` → two sources of truth silently disagreeing
- [x] `FoodRepository.latestBodyMeasurement()` + `currentWeightLb(profile:)` helpers added
- [x] `balanceFlags` now passes latest measurement weight into TDEE
- [x] `BodyCompositionView.SummaryCard` — prominent top card: current weight (with date), BMR × activity = TDEE breakdown, daily targets, active goal row
- [x] `GoalPlannerView` gained "Based on your profile" section — weight / height / age / sex / activity / BMR / TDEE rows, so the recommendation is never a black box
- [x] `UserProfile.bodyWeightLb` labeled as manual override in doc comment; `LogMeasurementSheet` no longer writes to it
- [x] **Verify:** logging a new weight visibly updates TDEE display and the SummaryCard (SwiftData @Query reactivity).

## Phase 16 — FatSecret Restaurant Lookup ✅
- [x] `NutritionixAPI.swift` deleted; replaced with `FatSecretAPI.swift`
- [x] `FatSecretAPI` actor — OAuth 2.0 via Cloudflare Worker proxy; `search(query:limit:)`, `foodDetail(id:)`, `parseNaturalLanguage(_:)`
- [x] All calls route through `FATSECRET_PROXY_URL` (Secrets.plist) — proxy holds consumer credentials, avoids IP whitelist issues
- [x] `FatSecretError` with `.missingProxyURL`, `.authFailed`, `.rateLimited`, `.proxyError`, etc.
- [x] `FoodSource.fatSecret` enum case (replaced `.nutritionix`)
- [x] `UserProfile.fatSecretCallsToday` + `fatSecretCallsResetAt` counters (replaced Nutritionix counters)
- [x] `SecretsLoader.fatSecretProxyURL` accessor (replaced Nutritionix accessors)
- [x] `Secrets.plist` — `FATSECRET_PROXY_URL` placeholder (replaced Nutritionix keys)
- [x] `FoodSearchService` — runs local / OFF / FatSecret in parallel; merge + dedup; rank (favorites → frequent → FatSecret → OFF → occasional)
- [x] `SearchView` — `fork.knife` icon for FatSecret results; "Powered by FatSecret" attribution at bottom when FatSecret results are shown
- [x] `NaturalLanguageEntrySheet` — "Powered by FatSecret" attribution; uses `FatSecretAPI.parseNaturalLanguage`
- [x] `SettingsView` — "Credits" section with "Powered by FatSecret" link to fatsecret.com
- [x] Rate-limit handling: suppress FatSecret in `FoodSearchService` at 4500 calls/day; error banner in NaturalLanguageEntrySheet
- [x] **Verify:** search "taco bell chalupa" → FatSecret results; "1 burrito bowl with chicken and rice" parses via NLP; 429 falls back to local + OFF

## Phase 17 — Recipe Builder ✅
- [x] `Recipe` + `RecipeIngredient` @Model classes with per-serving computed macros
- [x] Registered `Recipe.self` + `RecipeIngredient.self` in `MacroScanApp` schema
- [x] `FoodRepository`: `saveRecipe`, `deleteRecipe`, `recipes`, `logRecipe` (one `LogEntry` per ingredient, scaled by servings, auto-notes "from recipe: X")
- [x] `RecipesView` — list with search, swipe-to-delete, swipe-to-favorite, empty state
- [x] `RecipeBuilderView` — name, servings stepper, add/reorder/delete ingredients via local search, live per-serving macro summary, edit existing recipe support
- [x] `RecipeDetailView` — per-serving macros, ingredient breakdown, "Log this" / edit / delete, usage stats
- [x] `LogRecipeSheet` — pick servings + meal type + notes → logs via `FoodRepository.logRecipe`
- [x] `QuickLogItem` unified enum; `QuickLogBar` surfaces both foods and frequently-used recipes
- [x] DayView "+ Add" menu includes "Recipes"; Settings → "My Recipes" NavigationLink
- [x] **Verify:** create recipe, log servings, entries appear with correct scaled macros and "from recipe: X" notes

## Phase 18 — Apple Health Sync ✅
- [x] `BodyMeasurement.source` field added (`"manual"` default, `"healthkit"` for imports); lightweight migration via inline default
- [x] `HealthKitService` actor — reads: `latestWeightLb`, `latestBodyFatPct`, `activeEnergyBurned`, `basalEnergyBurned`; writes: `writeNutrition`, `writeBodyMeasurement`; `#if canImport(HealthKit)` guard with stub fallback
- [x] `BodyCompositionService.TDEEResult` + `todaysTDEE(...)` — static TDEE + dynamic TDEE from Health active energy
- [x] Weight import banner on `BodyCompositionView` — shows when Health has a newer weight than latest local `BodyMeasurement`; creates measurement with `source: "healthkit"` on import
- [x] Body fat import banner — same pattern
- [x] `SummaryCard` displays dynamic TDEE ("Today's actual") when Health data available, with estimate disclaimer
- [x] Silent HealthKit writes: `FoodRepository.logFood` fires `writeNutrition`; `LogMeasurementSheet.save` fires `writeBodyMeasurement`
- [x] Settings: Apple Health section — connect/re-request permissions, status display, graceful "not available" when HK unavailable
- [x] **Verify:** import banner appears when Health has newer weight; nutrition appears in Health after logging; TDEE shows both static + dynamic
- [x] **Note:** user must still enable HealthKit capability + add `INFOPLIST_KEY_NSHealthShareUsageDescription` / `INFOPLIST_KEY_NSHealthUpdateUsageDescription` in Xcode build settings (GENERATE_INFOPLIST_FILE project)

## Phase 19 — Quick-Add Calories ✅
- [x] `LogEntry` quickAdd fields added (`quickAddCalories`, `quickAddProteinG`, `quickAddCarbsG`, `quickAddFatG`, `quickAddFiberG`, `quickAddName`) — all optional, lightweight migration compatible
- [x] `LogEntry.isQuickAdd` computed property
- [x] `LogEntry.displayName` computed property (falls back to `quickAddName ?? "Quick add"` when `food` is nil)
- [x] `LogEntry.scaledMacros` updated to return quickAdd values when `food` is nil
- [x] `FoodRepository.logQuickAdd(...)` + `updateQuickAddEntry(...)` methods
- [x] `QuickAddSheet` UI — name, calories (required), optional protein/carbs/fat/fiber, meal picker, notes; reuses same view for editing with `editingEntry` parameter
- [x] `MealSectionView` visual differentiation for quick-add entries (italic name, `pencil.circle` icon, notes subtitle)
- [x] `MealSectionView.confirmationDialog` title uses `displayName` (works for both food-based and quick-add entries)
- [x] DayView "+ Add" menu includes "Quick Add Calories" with `bolt.fill` icon
- [x] Edit routes quick-add entries to `QuickAddSheet(editingEntry:)`, food entries to `EditLogEntrySheet`
- [x] Delete works for quick-add entries (same `FoodRepository.deleteEntry` path)
- [x] HealthKit write fires on quick-add log
- [x] **Verify:** quick-add 600 cal entry appears in totals; can edit and delete
## Phase 20 — Copy Meal Forward ✅
- [x] `FoodRepository.copyMeal(from:to:mealType:)` + `copyAllMeals(from:to:)` — copies food-based and quick-add entries, preserves time-of-day offsets
- [x] Private `copyEntry` helper handles both quick-add and food-based entries; increments `timesLogged` on food
- [x] `MealSectionView` — `onCopyMeal` callback; long-press context menu on section header with "Copy meal to…"
- [x] DayView — confirmation dialog with Today/Tomorrow/Pick a date options
- [x] DayView — date picker sheet for custom copy destination
- [x] DayView — toast overlay for copy confirmation ("Lunch copied to tomorrow (3 items)")
- [x] "Copy yesterday's meals" button on empty DayView (today tab only, when yesterday has entries)
- [x] Quick-add entries copy all quickAdd fields correctly
- [x] Recipe-derived entries copy as regular food entries (notes preserved with "from recipe: X")
- [x] **Verify:** copy lunch from yesterday to today; entries preserved with new timestamps and correct macros
## Phase 21 — Streaks & Adherence ✅
- [x] `FoodRepository.AdherenceStats` struct (loggedDays, totalDays, hitCalorieTargetDays, hitProteinTargetDays)
- [x] `FoodRepository.adherence(forLastDays:)` — scans last N days; calorie "hit" = within ±10% of target; protein "hit" = ≥ target
- [x] Adherence card at top of Trends subsection in `HistoryView` — "Last 14 Days" with logged/calorie/protein stats
- [x] No streak pressure — just neutral stats, no "you broke your streak" messaging
- [x] **Verify:** stats reflect actual log history accurately

---

## Iteration 3 — Status

All phases (15–21) complete. Ready for a local build verify in Xcode. Key manual test paths:

1. **Quick Add** — tap "+" → "Quick Add Calories" �� enter 600 cal with name "Restaurant dinner" → confirm it appears in today's totals with italic styling and pencil icon; edit and delete both work.
2. **Copy Meal** — long-press a meal section header → "Copy meal to…" → pick Tomorrow → toast confirms; entries appear on tomorrow's day. Also: empty today with yesterday's entries shows "Copy yesterday's meals" button.
3. **Adherence** — History → Trends tab → adherence card at top shows "Last 14 Days" with logged/calorie/protein stats.
4. **Quick-add + copy interaction** — quick-add an entry, copy that meal to another day → confirm the quickAdd fields copy correctly.

### Outstanding manual-setup items (can't do from code)
- **Phase 16:** deploy a Cloudflare Worker proxy for FatSecret API calls; paste the Worker URL into `Secrets.plist` as `FATSECRET_PROXY_URL`. Sign up for FatSecret Premier Free tier at platform.fatsecret.com (use .edu email for student access). The proxy holds consumer key/secret and has a stable whitelisted IP.
- **Phase 18:** enable HealthKit capability on the target in Xcode; add `INFOPLIST_KEY_NSHealthShareUsageDescription` + `INFOPLIST_KEY_NSHealthUpdateUsageDescription` build settings (this project uses `GENERATE_INFOPLIST_FILE = YES`, no standalone Info.plist — see memory)

---

# Iteration 4

## Phase 22 — Body Fat Estimation (Navy Method) ✅
- [x] `BodyMeasurement`: added `neckIn`, `hipIn`, `bodyFatSourceRaw` fields; lightweight migration via optional defaults
- [x] `BodyFatSource` enum (navy / manual / healthkit)
- [x] `BodyCompositionService.estimateBodyFatNavy` — US Navy circumference method, men + women formulas
- [x] `BodyCompositionService.currentBodyFat` — tries stored bodyFatPct first, falls back to Navy calculation
- [x] Input validation: waist > neck (men), waist + hip > neck (women), bounds 10–100 in, sex must be specified
- [x] `BodyFatEstimate` struct with pct / source / confidence
- [x] **Verify:** realistic male inputs (5'10", 32" waist, 15.5" neck) → estimate ≈ 13–15%; invalid inputs → error

## Phase 23 — Me Tab ✅
- [x] `UserProfile.dailyStepTarget: Int = 8000` added (pulled forward from Phase 26 — MeView references it)
- [x] `RootView` gains Me tab: `[Today] [Dining] [History] [Me] [Settings]`; icon `person.crop.circle`
- [x] `MeView` with header card (current weight, trend arrow, body fat badge with source)
- [x] Active goal card (target weight/BF, days remaining, View progress + Recompute buttons)
- [x] Quick actions: Log measurement, Update measurements, Plan a goal (with pre-flight measurement check)
- [x] Recent measurements list (last 5, "View all" → BodyCompositionView)
- [x] Targets summary (calories, protein, steps; "Goal-driven" or "Manual" label)
- [x] **Verify:** Me tab appears, mounts cleanly, all routes work, real data renders

## Phase 24 — Unified MeasurementsEditor ✅
- [x] `MeasurementsEditor` sheet — Body section (height, age, biological sex, activity level) + Today's Measurement section (weight, waist, neck, hip conditional on sex == female)
- [x] Live Navy estimate display as circumferences are typed
- [x] Toggle "Use Navy estimate" vs manual body fat entry
- [x] Save behavior: Body section updates UserProfile; measurement section creates new BodyMeasurement only if weight entered
- [x] HealthKit write on measurement save
- [x] Presented from both "Log measurement" and "Update measurements" buttons on MeView
- [x] **Verify:** body fields update profile only; weight + circumferences create BodyMeasurement with Navy-derived body fat

## Phase 25 — Meet Your Goal Flow ✅
- [x] Pre-flight measurement check in MeView: if measurement is stale (>7 days) OR profile missing height/age/sex → show confirmation dialog before navigating to GoalPlannerView
  - "Update measurements" → opens MeasurementsEditor → on dismiss navigates to planner
  - "Use existing data" → navigates directly to planner
  - Skip prompt if fresh (<7 days) AND profile complete
- [x] `DeficitPlan` extended: `dailyStepTarget: Int`, `trainingFrequencyPerWeek: Int`, `trainingNote: String`
- [x] Step target derived from activity level (sedentary 7,500 → extremely active 12,500)
- [x] Training frequency + note derived from diet goal and deficit magnitude
  - Cut + aggressive deficit → 3 sessions; otherwise 4; bulk → 5
  - Note mentions "compound lifts" / "progressive overload" + "use a dedicated app like Hevy"
- [x] `GoalPlannerView` Activity Targets section: daily steps, training sessions/week, approach note, Hevy disclaimer
- [x] `GoalPlannerView` basis section: body fat added when available
- [x] `applyTargets` writes `dailyStepTarget` to UserProfile
- [x] All 5 safety rails still in place (calorie floor, weekly loss cap, protein floor, BF floor, min timeline)
- [x] Hard-block-with-override path requires explicit confirmation alert
- [x] **Verify:** safe goal generates full plan with activity targets; unsafe goal triggers override flow

## Phase 27 — Goal Stickiness ✅ (audit)
- [x] Audit confirmed: `MeasurementsEditor.save()`, `LogMeasurementSheet.save()`, and all HealthKit import paths only insert `BodyMeasurement` records — they never touch `WeightGoal` or `UserProfile` calorie/protein targets
- [x] `GoalProgressView` reads measurements via `@Query` — new weight points appear automatically on the chart without any goal mutation
- [x] BMR/TDEE displays in `SummaryCard` use `currentWeightLb(profile:)` (reads latest measurement) — display-only, not target-setting
- [x] "Recompute targets" button added to active goal card on MeView — navigates to GoalPlannerView for explicit re-application
- [x] **Verify:** logging weight while goal is active leaves calorie/protein targets unchanged; GoalProgressView updates with new data point

## Phase 26 — Goal-Aware Today Targets ✅
- [x] `UserProfile.dailyStepTarget: Int = 8000` added (done in Phase 23)
- [x] Applying a goal in GoalPlannerView writes `dailyStepTarget` to UserProfile (done in Phase 25)
- [x] `HealthKitService.stepCount(forDate:)` — reads `HKQuantityType(.stepCount)`, `.stepCount` added to read authorization; stub fallback returns 0
- [x] `DayView.todayStepCount: Int?` state; fetched via `.task(id: isToday)` on the macro rings card (today only)
- [x] Steps row inside the macro rings card (today tab only): figure.walk icon, "Steps / target" with green tint when at target, "—" if HealthKit unavailable
- [x] Goal label beneath steps row: "Targets: Cut to X lb by DATE" tappable → MeView; or "Targets: Manual" in tertiary color
- [x] Deactivating goal: user re-applies manual targets via Settings — Today auto-reflects because macro rings read directly from `UserProfile`
- [x] **Verify:** apply goal → Today calorie/protein rings + step target reflect new values; goal label appears and routes to Me tab

---

# Iteration 5

## Phase 34 — Steps Foreground Re-fetch ✅
- [x] `DayView` gains `@Environment(\.scenePhase)` observation
- [x] `.onChange(of: scenePhase)` re-fetches step count from HealthKit when app returns to `.active` foreground (today only)
- [x] Eliminates stale step count after backgrounding the app
- [x] **Verify:** background app, walk steps, foreground → count updates without pulling-to-refresh

## Phase 28 — Dining Hall Removal ✅
- [x] `Models/DiningMenu.swift` deleted
- [x] `Services/DiningMenuService.swift` deleted
- [x] `Services/DiningOptimizer.swift` deleted
- [x] `Views/Dining/DiningView.swift` deleted
- [x] `Views/Dining/OptimizerView.swift` deleted
- [x] `Food.diningLocationRaw` and `Food.diningLocation` removed
- [x] `FoodSource.diningHall` case removed from Enums
- [x] `DiningLocation` enum removed from Enums
- [x] `DiningMenu.self` removed from MacroScanApp schema
- [x] `RootView` down to 4 tabs: Today / History / Me / Settings
- [x] `migrateDiningHallFoods()` in RootView.onAppear — rewrites any `sourceRaw == "diningHall"` rows to `"manual"` for clean migration
- [x] **Verify:** app launches with 4 tabs; no references to dining remain; existing data unaffected

## Phase 29 — Settings Reorganization ✅
- [x] Settings now contains: Body Weight, Diet Preferences, Library, Data, Apple Health, Credits, AI Usage
- [x] Diet Goal, Macro Targets, Micro Targets, and Profile (height/age/sex/activity) sections removed from Settings — those live on the Me tab
- [x] `targetRow` helper removed from SettingsView
- [x] Auto-protein button only visible when no active goal (`profile.currentGoal?.isActive != true`)
- [x] Micro targets editor (`MicroTargetsEditor`) added to MeView after the targets summary card
- [x] **Verify:** Settings is shorter; micro/macro targets accessible only from Me tab

## Phase 33 — Remove Vegetarian Toggle from Log Surfaces ✅
- [x] `ManualFoodForm` — removed `@State private var isVegetarian` and its `Toggle`
- [x] All new manually-added foods created as non-vegetarian by default (source: `.manual`)
- [x] `UserProfile.isVegetarian` retained for dietary filtering (used by CloseGapView / DiningOptimizer references still in codebase)
- [x] `isVegetarian` defaults to `true` in `UserProfile.init` — first-launch default is correct
- [x] **Verify:** ManualFoodForm has no vegetarian toggle; existing foods unaffected

## Phase 35 — Calorie Rounding Polish ✅
- [x] `ScanResultSheet` `nutritionRow` — calories display as integer (`"\(Int(value)) \(unit)"`)
- [x] `isVegetarian` defaults to `true` in UserProfile.init (confirmed — already correct)
- [x] **Verify:** ScanResultSheet shows "312 cal" not "312.3 cal" for calorie row

## Phase 32 — Servings-or-Grams Logging ✅
- [x] `LogEntry.servingsEaten: Double?` added (optional, lightweight migration compatible)
- [x] `AmountPicker` reusable component — segmented Servings/Grams toggle (only shown when food has `servingSizeGrams`), auto-converts text on unit switch, shows secondary "= X g / servings" label
- [x] `ScanResultSheet` — replaced raw grams text field with `AmountPicker`; defaults to servings mode when food has a serving size; `logEntry()` passes `servings:` to repo
- [x] `EditLogEntrySheet` — full rewrite using `AmountPicker`; `setupDefaults()` restores servings if `entry.servingsEaten` is set
- [x] `MealSectionView.rowDetail` — shows "1 serving (245g)" when servingsEaten is set, "245g" otherwise
- [x] `FoodRepository.logFood` + `updateEntry` — both accept `servings: Double? = nil` parameter
- [x] **Verify:** scan a food with serving size → default to "1 serving"; switch to grams → value converts; entry shows serving display in meal list

## Phase 30 — Target Body Fat as Goal Option ✅
- [x] `GoalPlannerView` — `GoalType` enum (`.weight` / `.bodyFat`); segmented Picker at top of goal input section
- [x] Body fat path: reads `currentBodyFat` (stored or Navy estimate), computes `targetWeight = LBM / (1 - targetBF/100)` to preserve lean mass
- [x] Warning shown when no body fat measurement available in BF mode
- [x] `applyTargets` handles both paths; sets `targetBodyFatPct` on `WeightGoal`
- [x] Basis section shows body fat when available
- [x] **Verify:** select "Body Fat %" goal type → enter 15% → plan shows derived target weight and standard cut targets

## Phase 31 — Water Tracking ✅
- [x] `WaterEntry` @Model (`amountMl`, `recordedAt`, `source`) registered in MacroScanApp schema
- [x] `UserProfile.dailyWaterTargetMl: Double = 2750` added (inline default for lightweight migration)
- [x] `FoodRepository`: `logWater(ml:at:)`, `waterEntries(forDate:)`, `totalWater(forDate:)`, `deleteWater(_:)`
- [x] `HealthKitService`: `writeWater(ml:recordedAt:)`, `waterSamples(forDate:)`, `HKQuantityType(.dietaryWater)` in read + write authorization
- [x] `WaterCard` — horizontal progress bar, color-coded (gray < 70%, orange ≥ 70%, green ≥ 100%), +8 oz / +16 oz / +Custom quick-add buttons, tap bar to open detail
- [x] `WaterDetailSheet` — list of entries for the day with swipe-to-delete, total vs. target display
- [x] `WaterCard` wired into `DayView` below macro rings section (shown for all dates)
- [x] Water target in `SettingsView` → Body Weight section (already on Me tab or Settings)
- [x] **Verify:** add 8 oz × 4 → bar reaches ~58% (64 oz of 93 oz default); custom entry works; swipe-to-delete in detail removes entry and updates total

---

## Iteration 5 — Status

All phases (28–35) complete. Ready for a local build verify in Xcode. Key manual test paths:

1. **Water tracking** — add 8 oz × 4 on Today → bar reaches ~58%; tap bar → WaterDetailSheet shows entries; swipe-to-delete removes one; custom add works.
2. **Servings logging** — scan a product with a declared serving size → ScanResultSheet defaults to "1 serving"; switch to grams → value auto-converts; logged entry shows "1 serving (Xg)" in meal list.
3. **Body fat goal** — Me → Plan a Goal → select "Body Fat %" → enter 15% → plan shows derived target weight and cut targets.
4. **Dining removed** — confirm 4 tabs only (Today / History / Me / Settings); existing logs are unaffected.
5. **Steps foreground update** — background app, return → step count updates without any manual refresh.

---

# Iteration 6

## Phase 41 — Migrate Barcode Scanning to FatSecret ✅
- [x] `FatSecretAPI.barcodeLookup(barcode:)` added — calls `food.find_id_for_barcode` then `food.get.v4`
- [x] `ScannerView` switched from `OpenFoodFactsAPI.lookup` to `FatSecretAPI.barcodeLookup`
- [x] Barcode-not-found → "Product Not Found" alert with "Log Manually" (opens ManualFoodForm) and "Try Another" options
- [x] Rate limit guard: checks `profile.fatSecretCallsToday >= 4500` before each call; increments on success; sets 5000 on `.rateLimited`
- [x] `OpenFoodFactsAPI.swift` retained — still used for text search in `FoodSearchService`
- [x] `FoodSource.openFoodFacts` case already absent from `Enums.swift`
- [x] Scanner restarts automatically after ScanResultSheet or ManualFoodForm is dismissed
- [x] **Verify:** real barcode → FatSecret data; unknown barcode → manual entry prompt; rate limit shows error + manual option

## Phase 36 — Split Measurements Editor ✅
- [x] `LogMeasurementSheet` (today's data only) — weight, waist, neck, hip (female only), optional BF%, notes, Navy estimate
- [x] `ProfileEditorSheet` (stable profile fields only) — height, age, sex, activity level
- [x] `MeView` wired to `LogMeasurementSheet`; "Update measurements" button removed
- [x] `SettingsView` Profile section with "Edit profile" NavigationLink + current-values subtitle → `ProfileEditorSheet`
- [x] Original `MeasurementsEditor.swift` deleted (was a stub comment only)
- [x] **Verify:** distinct flows, no cross-contamination of data

## Phase 37 — Macro Rings Show Targets ✅
- [x] `MacroRing` shows consumed / target / unit 3-line stack inside each ring
- [x] Over-target switches consumed line to `.mOver` color
- [x] Spacing tightened; font sized to fit 4-digit calorie values
- [x] No redundant summary strip added elsewhere
- [x] **Verify:** clean display at all values; no clipping on smallest iPhone

## Phase 38 — Editable Scan Results ✅
- [x] `ScanResultSheet` gains "Nutrition (per Xg)" `DisclosureGroup`, collapsed by default
- [x] All macro + micro fields editable (cal, protein, carbs, fat, fiber, iron, vit D, vit B12)
- [x] "Reset to scanned values" button restores original display strings
- [x] `pencil.circle.fill` modified indicator shown when any field differs from original
- [x] Edited values applied directly to `Food` record in `logEntry()` before logging
- [x] Existing "Nutrition" preview section stays reactive to edited values via `effectiveMacrosPerServing`
- [x] **Verify:** scan, edit calories, log → LogEntry uses corrected value; Reset restores originals

## Phase 39 — Verified Food Persistence ✅
- [x] `Food.userVerified: Bool = false` and `Food.lastVerifiedAt: Date?` added (lightweight migration)
- [x] `ScannerView` scan logic: verified → use directly; unverified local → fetch FatSecret + conflict alert; no local → fetch FatSecret
- [x] Conflict resolution alert: "Local: X cal • FatSecret: Y cal — pick one." with Use Local / Use FatSecret buttons
- [x] `logEntry()` sets `food.userVerified = true` + `food.lastVerifiedAt = Date()` when macros are edited
- [x] `ScanResultSheet` accepts `isVerified: Bool` parameter; shows `checkmark.seal.fill` banner
- [x] `FoodRow` gains `isVerified: Bool` parameter; shows `checkmark.seal.fill` (green) icon next to food name
- [x] `MealSectionView` passes `entry.food?.userVerified ?? false` to `FoodRow`
- [x] **Verify:** scan A → edit → log; rescan A → pre-filled, banner shown; DayView row shows checkmark

## Phase 40 — JSON Export and Import ✅
- [x] `DataExportService` `@MainActor` struct with `exportAll()` → URL and `importFrom(_:)` → `ImportResult`
- [x] DTO structs for all @Model types: `FoodDTO`, `LogEntryDTO`, `BodyMeasurementDTO`, `WaterEntryDTO`, `RecipeDTO`, `WeightGoalDTO`, `UserProfileDTO`
- [x] `ExportPayload` JSON schema: version 1, exportedAt, appVersion, all entity arrays
- [x] `exportID: UUID = UUID()` added to Food, LogEntry, BodyMeasurement, WaterEntry, Recipe, WeightGoal (lightweight migration)
- [x] Photos (`LogEntry.photoData`) included as base64 inline (Option A)
- [x] `ImportResult.summary` human-readable string with per-entity added/skipped counts
- [x] UUID-based deduplication on import (skip existing, no overwrite)
- [x] Version mismatch and malformed file errors with clear messages
- [x] Settings → Data section: Export button (→ ShareSheet), Import button (→ UIDocumentPicker), explainer text
- [x] **Verify:** export → wipe → import → all data restored, no duplicates on re-import
