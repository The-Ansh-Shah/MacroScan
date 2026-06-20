# MacroScan — Build Instructions (Iteration 3)

Reference: [ARCHITECTURE.md](ARCHITECTURE.md), [PROGRESS.md](PROGRESS.md), [INSTRUCTIONS.md](INSTRUCTIONS.md) (iteration 2)

This iteration closes real gaps in everyday use:

1. **Measurement-flow audit** — body measurements aren't currently affecting TDEE, recommended targets, or goal planning. Diagnose and fix.
2. **FatSecret restaurant lookup** — add a third search source for restaurant chain items (Taco Bell, Chipotle, etc.)
3. **Recipe builder** — combine multiple `Food`s into a saved meal you can log as one item
4. **Apple Health sync** — bidirectional: read weight + workouts, write nutrition + measurements
5. **Quick-add calories** — log a calorie/macro estimate without finding or creating a `Food`
6. **Copy meal forward** — duplicate a past day's meal into today
7. **Streaks & adherence** — small, no-pressure stats

Read the entire document before beginning. Update `PROGRESS.md` as items complete.

**Build order matters here.** Phase 15 (audit) is first because it's a bug, not a feature — it's likely already broken in ways the user can't see, and adding more features on top of broken plumbing makes everything harder to debug later.

---

## Phase 15 — Measurement-Flow Audit (BUG FIX, do first)

### Symptom
The user reports: "the app currently takes information like measurements and all, but doesn't do anything with it." They can log body measurements via `BodyCompositionView`, but they don't observe the data affecting TDEE, recommended targets, or goal projections.

### Investigation checklist

Audit each of the following and document findings inline as you go:

1. **`BodyCompositionService.computeBMR`** — does it read from the latest `BodyMeasurement.weightLb`, or from a stale `UserProfile.bodyWeightLb`? It should prefer the latest measurement and fall back to profile only if no measurements exist.
2. **`BodyCompositionService.computeTDEE`** — same check. Confirm height/age/sex/activity all come from the right places.
3. **Reactive updates**: when a new `BodyMeasurement` is inserted, do `GoalPlannerView`, `BodyCompositionView`, and `GoalProgressView` re-render with the new value? SwiftData `@Query` should handle this — verify it does.
4. **Target recomputation**: if the user has an active `WeightGoal`, does logging a new weight update the projected progress in `GoalProgressView`? Does it trigger any recomputation of recommended `dailyCalorieTarget` / `dailyProteinTargetG`? Per spec it shouldn't auto-overwrite (user explicitly chose those when applying the plan), but the *projected progress chart* must reflect the new weight.
5. **`UserProfile.bodyWeightLb`**: is this still being used anywhere? If yes, decide: deprecate it in favor of "latest BodyMeasurement," or keep it as a manual override. Don't have two sources of truth silently disagreeing.
6. **Goal active state**: when a `WeightGoal` is active, is `GoalProgressView` actually showing it on `BodyCompositionView` or in Settings? User should be able to find it without hunting.
7. **First-launch path**: `ProfileSetupView` collects measurements — does the initial `BodyMeasurement` it creates flow through to all the views correctly? Or does it sit orphaned in the database?

### Fixes

For each break found:

- Refactor reads to consistently prefer the latest `BodyMeasurement` over `UserProfile.bodyWeightLb`. Add a helper: `FoodRepository.latestBodyMeasurement() -> BodyMeasurement?` if it doesn't exist.
- Make `BodyCompositionView` show, prominently at top: current weight, current TDEE (with breakdown: BMR + activity multiplier), current targets, active goal status (if any).
- Make `GoalPlannerView` show the inputs that drove the recommended plan ("based on your current weight of 168 lb, height 5'10", age 20, moderate activity"). User should never wonder *why* the recommendation is what it is.
- Add a clear surfacing on `SettingsView` or `BodyCompositionView` that says: "TDEE: 2,640 kcal/day (BMR 1,705 × Moderate activity 1.55). Recommended cutting target: 2,140 kcal." This makes the data visibly *doing something*.

### Out of scope for this phase
Don't auto-recompute targets when weight changes. That's a deliberate user action via `GoalPlannerView`. The projected progress chart can update automatically; the targets cannot.

### Verify
- Log a new weight in `BodyCompositionView` → TDEE display updates immediately
- Open `GoalPlannerView` → inputs shown match latest measurement
- Open `GoalProgressView` for an active goal → chart includes the new weight point
- Confirm `UserProfile.bodyWeightLb` either fully removed or clearly labeled as manual override

---

## Phase 16 — FatSecret Restaurant Lookup

### Why
Open Food Facts covers packaged goods well but not restaurant items. The user wants to log a Taco Bell Chalupa or Chipotle bowl by name.

### Provider choice (context for why this is FatSecret)

Nutritionix was the original plan but shut down their free tier in 2025 due to abuse (paid tiers now start at $1,850/month — unusable for personal projects). FatSecret offers a **"Premier Free"** tier specifically for students, startups under $1M revenue, and non-profits. It includes full Premier access to the US dataset (branded foods, restaurant items, natural-language parsing, auto-complete, barcode lookup) with attribution required. As a UC Berkeley student, the user qualifies directly.

Database coverage: 2.3M foods across 58 countries; US dataset alone includes branded, supermarket, and restaurant items. Attribution requirement is easy to satisfy: a small "Powered by FatSecret" label on search results rows or the settings screen.

### API setup

1. Register at https://platform.fatsecret.com/register
2. Request Premier Free access during signup — select "Student" as the account type. Provide a .edu email (user has one through Berkeley) to speed verification.
3. Under the account dashboard, create an API Application. Capture:
   - `Consumer Key` (aka `OAuth Consumer Key`)
   - `Consumer Secret`
4. Add the allowed IP addresses (FatSecret whitelists IPs at the application level — for development this can be your home IP; for production use, consider proxying through a server). **This is a real friction point — see "IP whitelist caveat" below.**
5. Add to `Secrets.plist`:
   - `FATSECRET_CONSUMER_KEY`
   - `FATSECRET_CONSUMER_SECRET`

### IP whitelist caveat (read this before starting)

FatSecret's Platform API restricts requests to whitelisted IPs. This is fine for server-to-server, awkward for a phone app where the IP changes every time the user switches Wi-Fi. Two paths:

- **Path A (simpler, recommended):** proxy FatSecret calls through a minimal serverless function (Cloudflare Worker, free tier). The Worker holds the FatSecret credentials and has a stable IP that's whitelisted. The iOS app calls the Worker, which calls FatSecret. Adds ~100ms latency and one tiny deployment, but avoids the whitelist nightmare.
- **Path B (direct):** call FatSecret directly from the device and whitelist a broad IP range or use OAuth 2.0 with dynamic IP tokens (FatSecret supports this on newer API versions). This is fiddlier; skip unless comfortable.

Assume Path A. A `fatsecret-proxy` Cloudflare Worker (~30 lines of JS) that forwards signed OAuth requests to FatSecret and returns JSON. Deploy from a separate repo; don't bundle with the iOS project.

### Authentication

FatSecret's older Platform API uses **OAuth 1.0** signed requests — annoying but documented. The newer v3/v4 endpoints support **OAuth 2.0 client credentials flow** which is much simpler: POST consumer key + secret to token endpoint, get a bearer token, use it for ~24 hours. Use OAuth 2.0.

Token endpoint: `https://oauth.fatsecret.com/connect/token` with `grant_type=client_credentials` and scope `basic` (or `premier` for Premier features).

### Service

New `FatSecretAPI` actor:

```swift
actor FatSecretAPI {
    enum FatSecretError: Error {
        case missingCredentials
        case authFailed
        case rateLimited
        case notFound
        case networkError(Error)
        case decodingError(Error)
        case proxyError(String)
    }
    
    // Auto-refreshing OAuth 2.0 token
    private var cachedToken: (value: String, expiresAt: Date)?
    private func bearerToken() async throws -> String { ... }
    
    // Text search — returns both generic and branded/restaurant items
    // Uses `foods.search.v3` with include_food_images=false for speed
    func search(query: String, limit: Int = 10) async throws -> [Food]
    
    // Natural language processing — "1 chalupa with refried beans"
    // Uses `natural_language_processing` endpoint (Premier feature, included in Free tier)
    func parseNaturalLanguage(_ text: String) async throws -> [Food]
    
    // Get full detail for a specific food ID (needed for full nutrition panel
    // including fiber + micros, since search returns abbreviated info)
    func foodDetail(id: String) async throws -> Food
}
```

All calls route through the Cloudflare Worker proxy URL stored in `Secrets.plist` as `FATSECRET_PROXY_URL`.

### Enum addition

```swift
enum FoodSource {
    case barcode
    case aiVision
    case manual
    case diningHall
    case fatSecret   // new
}
```

Update any existing exhaustive switches.

### `FoodSearchService` integration

Extend the existing search service to query FatSecret as a third source:

1. Local DB (existing)
2. Open Food Facts (existing)
3. FatSecret (new) — best for restaurant items

Run all three in parallel. Merge with dedup on (name + brand) similarity. Ranking:
- Local favorites first
- Local frequently-eaten next
- FatSecret results next (these are high-quality for restaurant queries and branded foods)
- Open Food Facts results after
- Local rarely-used at the bottom

In `SearchView`, distinguish source with a small icon:
- `house.fill` for local
- `barcode` for Open Food Facts
- `fork.knife` for FatSecret

### Natural-language entry

Add a new entry mode in `DayView` "+ Add" menu: **"Describe what you ate"**.

- Opens a sheet with a text field: "e.g., 1 burrito bowl with chicken and rice"
- Submit → calls `FatSecretAPI.parseNaturalLanguage`
- Result(s) appear in a confirm sheet — user can adjust quantities and meal type, then log
- Each parsed item becomes a `Food` saved locally for future quick-log
- Multiple foods from one query → multiple `LogEntry` rows in the same meal slot

### Search detail flow

FatSecret's search returns abbreviated nutrition (typically only calories + a short macro summary). For a full log with fiber + micros, the flow is:

1. User types query → `search()` returns candidate list
2. User taps a result → `foodDetail(id:)` fetches full nutrition
3. Detail populates a pre-filled log sheet (same pattern as the OFF flow)

This keeps the search endpoint snappy and only pays the detail cost for selected items.

### Attribution requirement

The Premier Free tier requires visible attribution. Easy to satisfy:

- Small "Powered by FatSecret" text at the bottom of `SearchView` when FatSecret results appear
- Link to `https://www.fatsecret.com` from Settings → "About / Credits" section

### Rate limit handling

Premier Free tier limits are generous (~5000 calls/day per reports). Track locally anyway:

- `UserProfile.fatSecretCallsToday: Int`, `fatSecretCallsResetAt: Date`
- On 429: surface a toast, fall back to local + OFF only
- On auth failure: clear the cached token and retry once; if still failing, surface a Settings prompt ("FatSecret authentication expired — check API credentials")

### Privacy note

Queries route through your own proxy and then to FatSecret's servers. Standard API usage. No different from any other search provider.

### Verify
- Search "taco bell chalupa" → FatSecret results appear with brand + calorie info
- Tap a result → detail fetched, full macros visible on the log sheet
- Natural-language entry: "1 burrito bowl with chicken and rice" → parses to one or more foods
- Search results from all three sources appear together, properly ranked
- "Powered by FatSecret" attribution visible when FatSecret results are shown
- Force a 429 (mock or temporarily block the proxy) → graceful fallback to local + OFF

---

## Phase 17 — Recipe Builder

### Why
Anything cooked at home (oatmeal + protein powder + peanut butter; rice bowl with tofu and veggies; smoothie) currently requires logging 3-5 separate items every time. A recipe is a saved combination — define once, log servings of it forever.

### Data model

```swift
@Model
final class Recipe {
    var name: String
    var notes: String?
    var totalServings: Double
    var ingredients: [RecipeIngredient]
    var createdAt: Date
    var lastUsedAt: Date?
    var timesUsed: Int
    var isFavorite: Bool
    
    // Computed per-serving macros — recompute on read, don't persist
}

@Model
final class RecipeIngredient {
    var recipe: Recipe?
    var food: Food?
    var grams: Double
    var order: Int
}
```

### Service

Extend `FoodRepository`:

```swift
func saveRecipe(_ recipe: Recipe) throws
func deleteRecipe(_ recipe: Recipe) throws
func recipes(favoritesFirst: Bool = true) -> [Recipe]
func logRecipe(_ recipe: Recipe, servings: Double, mealType: MealType, loggedAt: Date, notes: String?) throws -> [LogEntry]
```

`logRecipe` creates one `LogEntry` *per ingredient*, scaled by `servings / recipe.totalServings`. This preserves macro accuracy and means deleting/editing the recipe later doesn't retroactively change historical logs.

Each generated `LogEntry` gets `notes` auto-populated: `"from recipe: <recipe name>"`.

Increment `timesUsed` and update `lastUsedAt` on every log.

### Views

**`RecipesView`** — accessible from a toolbar button on `DayView` and from `Settings → My Recipes`.
- List of saved recipes, search bar at top, "+ New Recipe" button
- Each row: name, total servings, per-serving calorie/protein at a glance, last-used date, favorite star
- Swipe to delete or favorite. Tap to open `RecipeDetailView`

**`RecipeBuilderView`** (new + edit)
- Name field
- Total servings stepper (default 1, fractional allowed)
- Ingredient list (drag to reorder)
- "+ Add Ingredient" → opens `SearchView` to find a `Food`, then asks for grams
- Live-updating per-serving macros at the top (sticky header)
- Save / Cancel toolbar
- Optional notes field

**`RecipeDetailView`**
- Recipe name + per-serving macros prominently
- Ingredient breakdown
- "Log this" button → sheet to pick servings + meal type + date + notes → calls `logRecipe`
- Edit / Delete in toolbar

### Quick-log integration

`MealRanker` ranks foods by `timesLogged * recencyWeight`. Extend to also surface frequently-used recipes.

New unified type:

```swift
enum QuickLogItem: Identifiable {
    case food(Food)
    case recipe(Recipe)
}
```

`QuickLogBar` shows mixed foods + recipes with distinct icons.

### Verify
Create a recipe (e.g., "Morning oats" — 80g oats + 30g whey + 20g peanut butter, 1 serving). Log 1 serving at breakfast. Confirm three `LogEntry` rows appear with correct scaled macros and "from recipe: Morning oats" in notes.

---

## Phase 18 — Apple Health Sync

### Why
Single biggest integration win on iOS. Weigh-ins from a smart scale flow into the app for free. Activity data adjusts TDEE based on actual movement. Nutrition data lives alongside everything else in Health.

### Permissions

Add `HealthKit` capability to the target. In `Info.plist`:
- `NSHealthShareUsageDescription`: "MacroScan reads your weight and activity to keep nutrition targets accurate."
- `NSHealthUpdateUsageDescription`: "MacroScan writes your nutrition and body measurements to Health so all your data lives in one place."

### Service

```swift
actor HealthKitService {
    func requestAuthorization() async throws
    
    // READ
    func latestWeightLb() async throws -> (lb: Double, recordedAt: Date)?
    func latestBodyFatPct() async throws -> (pct: Double, recordedAt: Date)?
    func activeEnergyBurned(forDate: Date) async throws -> Double  // kcal
    func basalEnergyBurned(forDate: Date) async throws -> Double   // kcal
    
    // WRITE
    func writeNutrition(_ logEntry: LogEntry) async throws
    func writeBodyMeasurement(_ measurement: BodyMeasurement) async throws
}
```

### Read flow — weight import

- On app launch and when `BodyCompositionView` opens, call `latestWeightLb()`
- If a Health weight is newer than the most recent `BodyMeasurement`, show a banner: "New weight from Health: 168.4 lb on Apr 22 — Import?"
- On import: create `BodyMeasurement` with that weight, timestamp, and `source: "healthkit"`
- Same flow for body fat %

Never auto-import without confirmation.

### Read flow — activity-adjusted TDEE

```swift
struct TDEEResult {
    let staticTDEE: Double      // from BMR × activityLevel
    let dynamicTDEE: Double?    // BMR + today's active energy from Health
    let source: TDEESource      // .static or .dynamic
}

extension BodyCompositionService {
    func todaysTDEE(profile: UserProfile, healthData: HealthDataSnapshot?) async -> TDEEResult
}
```

Show both on `BodyCompositionView` and `GoalPlannerView`. Goal planning uses `staticTDEE` as the baseline (you can't plan around future variable activity); `dynamicTDEE` shown as "today's actual" comparison.

**Do not auto-add exercise calories to the daily intake budget.** This is the trap — exercise estimates are noisy and "earning back" calories encourages overeating. Surface the data; let the user adjust manually if they want.

### Write flow

- After each successful log: write nutrition data points (calories, protein, carbs, fat, fiber) using `HKQuantitySample` with appropriate identifiers
- After each `BodyMeasurement` save: write to Health as `bodyMass` / `bodyFatPercentage`
- Writes are silent. Failure: log to console, do not interrupt user

### Settings UI

New section in `SettingsView`: **"Apple Health"**
- Connection status: connected / not connected / partially authorized
- Toggles per data type (read weight, read activity, write nutrition, write body measurements)
- "Re-request permissions" button
- Last sync timestamp

### `BodyMeasurement` schema addition

```swift
@Model
final class BodyMeasurement {
    // ... existing fields ...
    var source: String  // "manual" | "healthkit"
}
```

Default existing rows to "manual" via lightweight migration.

### Edge cases

- HealthKit unavailable (sim, iPad without HealthKit) → service no-ops, settings shows "Not available on this device"
- User denies all permissions → no repeated prompting; show inline "Connect in Settings"
- Multiple weight samples for a day → use most recent

### Verify
- On a physical phone with weight in Health: open `BodyCompositionView`, see import banner, tap to import, confirm new measurement appears
- After logging a food, open Apple Health → Browse → Nutrition → confirm calories/protein appear
- TDEE display shows both static and dynamic when activity data available

---

## Phase 19 — Quick-Add Calories

### Why
Restaurants, friend's house, anywhere you're guesstimating. You know it was ~600 cal but don't want to find or create a `Food`.

### Data model

```swift
@Model
final class LogEntry {
    var food: Food?
    var gramsEaten: Double               // 0 for quick-adds
    
    // Quick-add fields (food == nil)
    var quickAddCalories: Double?
    var quickAddProteinG: Double?
    var quickAddCarbsG: Double?
    var quickAddFatG: Double?
    var quickAddFiberG: Double?
    var quickAddName: String?
    
    // Computed macros — checks food first, falls back to quickAdd
}
```

Lightweight migration: existing entries have nil quickAdd fields, food set, behaves as before.

### View

`QuickAddSheet`:
- Name field (optional, e.g., "Restaurant dinner")
- Calories (required)
- Protein, carbs, fat, fiber (optional)
- Meal type picker
- Date/time
- Notes
- Save → `LogEntry` with `food = nil` and quickAdd values populated

### Display

Quick-add entries in `MealSectionView`:
- Italic name (or "Quick add" if name missing)
- Subtle visual differentiation — lower-contrast background or `pencil` SF Symbol
- Edit and delete behave like food-based entries

### Access

`DayView` "+ Add" menu now includes:
- Search foods
- Scan barcode
- Snap photo
- Describe what you ate (Phase 16)
- Quick add calories ← new
- Recipes (Phase 17)

### Verify
Quick-add a 600 cal entry. Confirm it appears in totals, can be edited (changing calories updates macros), can be deleted.

---

## Phase 20 — Copy Meal Forward

### Why
Same lunch every weekday. Currently re-logged from scratch.

### UX

On any meal section header on a day with logged entries:
- Long-press → action sheet: **"Copy meal to..."**
- Sheet shows: today, tomorrow, custom date picker
- Pick destination → all entries in that meal copied to destination day's same meal
- Each copied entry preserves grams, food relationship, notes; new `loggedAt` timestamp; new entry IDs
- Quick-add entries copy their quickAdd values
- Recipe-derived entries copy as-is (still tagged "from recipe: X")
- Confirmation toast: "Lunch copied to tomorrow"

Also surface as button on `DayView`: "Copy yesterday's meals" — one tap copies all of yesterday's entries to today, preserving meal types. Only shown when today has zero entries.

### Service

```swift
extension FoodRepository {
    func copyMeal(from sourceDate: Date, to destDate: Date, mealType: MealType) throws -> Int
    func copyAllMeals(from sourceDate: Date, to destDate: Date) throws -> Int
}
```

Returns number of entries copied (for the toast).

### Verify
Copy lunch from yesterday to today. Confirm all entries appear with new timestamps and macros total correctly.

---

## Phase 21 — Streaks & Adherence

Tiny addition. No gamification.

### Compute

```swift
extension FoodRepository {
    struct AdherenceStats {
        var loggedDays: Int
        var totalDays: Int
        var hitCalorieTargetDays: Int
        var hitProteinTargetDays: Int
    }
    
    func adherence(forLastDays days: Int) -> AdherenceStats
}
```

### Display

In the **Trends** subsection of `HistoryView`, add a top card:
- "Logged 12 of last 14 days"
- "Hit calorie target 9 days"
- "Hit protein target 11 days"

That's it. No streak counter that pressures the user. No "you broke your streak!" messaging. Just stats.

### Verify
Stats reflect actual log history.

---

## Progress updates

Append to `PROGRESS.md`:

```markdown
# Iteration 3

## Phase 15 — Measurement-Flow Audit (BUG FIX)
- [ ] Audit BodyCompositionService for stale weight reads
- [ ] Audit GoalPlannerView / GoalProgressView reactivity to new measurements
- [ ] Add FoodRepository.latestBodyMeasurement() helper
- [ ] BodyCompositionView shows current weight + TDEE breakdown + targets + active goal prominently
- [ ] GoalPlannerView shows the inputs that drove the recommendation
- [ ] Resolve UserProfile.bodyWeightLb dual-source-of-truth issue (deprecate or label as manual override)
- [ ] **Verify:** logging a new weight visibly updates TDEE display and projection chart

## Phase 16 — FatSecret Restaurant Lookup
- [ ] Sign up for FatSecret Premier Free tier (.edu email, student status)
- [ ] Deploy minimal Cloudflare Worker proxy (FATSECRET_PROXY_URL)
- [ ] Add FATSECRET_CONSUMER_KEY + FATSECRET_CONSUMER_SECRET to proxy (not iOS app)
- [ ] FatSecretAPI actor: OAuth 2.0 bearer token caching, search, natural language, foodDetail
- [ ] FoodSource.fatSecret enum case
- [ ] FoodSearchService extended to query all three sources in parallel
- [ ] SearchView source icons distinguishing local / OFF / FatSecret
- [ ] "Describe what you ate" entry mode in DayView + Add menu
- [ ] "Powered by FatSecret" attribution in SearchView + Settings credits
- [ ] Rate-limit handling with daily counter on UserProfile
- [ ] Detail fetch on selection (search returns abbreviated nutrition)
- [ ] **Verify:** searching "taco bell chalupa" returns valid macros via detail fetch; natural-language entry parses multi-item queries

## Phase 17 — Recipe Builder
- [ ] Recipe + RecipeIngredient @Models
- [ ] FoodRepository: saveRecipe / deleteRecipe / recipes / logRecipe
- [ ] RecipesView (list, search, favorite, delete)
- [ ] RecipeBuilderView (new + edit, drag-reorder, live macros)
- [ ] RecipeDetailView with "Log this" flow
- [ ] QuickLogItem unified type; QuickLogBar surfaces recipes
- [ ] Toolbar button on DayView; Settings → My Recipes link
- [ ] Auto-notes "from recipe: X" on generated LogEntries
- [ ] **Verify:** create a recipe, log servings, entries appear with correct macros

## Phase 18 — Apple Health Sync
- [ ] HealthKit capability + Info.plist usage descriptions
- [ ] HealthKitService actor: read weight, body fat, active/basal energy
- [ ] HealthKitService actor: write nutrition + body measurements
- [ ] BodyMeasurement.source field with migration
- [ ] Weight import banner on BodyCompositionView (confirmation required)
- [ ] BodyCompositionService.todaysTDEE with static + dynamic results
- [ ] BodyCompositionView shows static + dynamic TDEE
- [ ] Settings: Apple Health section with per-type toggles + status
- [ ] Silent writes after each LogEntry + BodyMeasurement save
- [ ] Graceful no-op when HealthKit unavailable or denied
- [ ] **Verify:** real weigh-in from Health imports; nutrition appears in Health app

## Phase 19 — Quick-Add Calories
- [ ] LogEntry quickAdd fields + lightweight migration
- [ ] LogEntry computed macros handle nil food correctly
- [ ] QuickAddSheet UI
- [ ] MealSectionView visual differentiation for quick-adds
- [ ] DayView "+ Add" menu includes Quick Add
- [ ] Edit + delete work for quick-add entries
- [ ] **Verify:** quick-add 600 cal entry appears in totals; can edit and delete

## Phase 20 — Copy Meal Forward
- [ ] Long-press on meal section header → copy-to-date sheet
- [ ] FoodRepository.copyMeal + copyAllMeals
- [ ] "Copy yesterday's meals" button on empty DayView
- [ ] Quick-add and recipe entries copy correctly
- [ ] Confirmation toast on copy
- [ ] **Verify:** copy lunch to tomorrow; entries preserved with new timestamps

## Phase 21 — Streaks & Adherence
- [ ] FoodRepository.adherence(forLastDays:)
- [ ] AdherenceStats card at top of Trends subsection
- [ ] **Verify:** stats reflect actual log history accurately
```

---

## Build Order Note

Strict order matters here:

1. **Phase 15 first** — it's a bug, not a feature. Fix the plumbing before adding more weight to it.
2. **Phase 16** — gives the app real-world utility (restaurant logging).
3. **Phase 17** — recipes are the highest single-impact convenience addition.
4. **Phase 18** — longest of the four feature phases. Budget 4-5 hours; HealthKit auth flows are fiddly. Test on physical device, not simulator.
5. **Phases 19, 20, 21** — quick wins, ~1-2 hours each. Bundle in one focused session if momentum is good.

After Phase 19, the app has every logging primitive a serious tracker needs: barcode, photo, search (local + OFF + FatSecret), natural-language, recipe, manual food, quick-add. From that point on, it's all convenience.

## Constraints

- Follow `ARCHITECTURE.md` §15 conventions
- No new external Swift packages — FatSecret is a REST API, HealthKit is Apple framework
- No new AI integrations
- Every new view uses DesignSystem tokens
- Commit after each phase passes verify
- Disclaimers on Health-data-derived recommendations: "Active energy from Health is an estimate; do not rely on it for precise calorie balancing."
- FatSecret data is community-contributed with moderation; not all entries are lab-verified. Treat it as directionally accurate — close enough for daily tracking, not precise enough for medical/clinical use. No new disclaimer needed beyond the existing AI confidence pattern.