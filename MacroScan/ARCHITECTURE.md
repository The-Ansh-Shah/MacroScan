# MacroScan — Architecture

A personal iOS food logging app. Barcode scanning, minimal AI image recognition, Berkeley dining hall optimizer, macro + micro tracking. Cutting-focused with configurable targets. Vegetarian with egg/mushroom exclusions. Native iOS aesthetic with SF Rounded and functional color.

---

## 1. Scope and Non-Goals

**In scope (v1):**
- Barcode scanning → Open Food Facts lookup
- Image capture → Gemini 2.5 Flash for *identification + macro estimation only* (the one and only AI call in the app)
- Manual food entry
- Per-meal logging (breakfast/lunch/dinner/snack)
- Daily view with macro + fiber + micro totals vs. targets
- 7-day history and trend stats
- Local meal ranking by eating patterns (pure algorithm, no AI)
- Berkeley dining hall optimizer (pending data verification — see §7)
- Dietary preferences (vegetarian, exclusions) enforced across all features
- Cutting-focused defaults, fully configurable targets

**Out of scope (v1, candidates for later):**
- Workout logging (Hevy covers this)
- iCloud sync (local-only first; CloudKit migration path kept clean)
- Apple Health read/write
- Social / sharing features
- Recipe builder (multi-ingredient home dishes logged as single food)
- AI-generated meal suggestions (replaced with deterministic ranking)

**Non-goals, period:**
- App Store publication (personal use)
- Supporting iOS < 17
- Other platforms

---

## 2. AI Usage Philosophy

AI is expensive (latency, rate limits, unpredictability). The app calls an LLM **exactly once per code path**, and only on the photo-capture flow.

**AI fires when:**
- User taps "Photo" on an unknown food → Gemini identifies food + estimates grams + estimates macros/micros

**AI does not fire when:**
- Scanning a barcode → Open Food Facts (deterministic HTTP)
- Picking from Recent / Favorites → local DB
- Logging a dining hall item → scraped menu data
- Manual entry → form
- Getting meal suggestions → local ranking algorithm
- "Close the gap" suggestions → constraint-satisfying filter over personal food DB

**Natural decay property:** Each photo analysis saves the resulting `Food` to local DB. Next time you eat it, it's in Recent — no AI call. After a few weeks of use, AI calls trend toward ~2-3/week.

---

## 3. Stack

| Layer | Choice |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI |
| Persistence | SwiftData |
| Min iOS | 17.0 |
| Barcode scanning | AVFoundation |
| Nutrition DB (packaged foods) | Open Food Facts |
| Nutrition DB (dining halls) | Cal Dining scraper (backend TBD) |
| AI vision | Gemini 2.5 Flash (only on photo path) |
| Concurrency | Swift async/await + actors |
| Charts | Swift Charts (built-in) |
| External packages | Zero for v1 |

---

## 4. Directory Layout

```
MacroScan/
├── MacroScanApp.swift
├── CLAUDE.md                       // Project conventions for Claude Code
├── Secrets.xcconfig                // GEMINI_API_KEY (gitignored)
├── Info.plist
│
├── Models/
│   ├── Food.swift
│   ├── LogEntry.swift
│   ├── UserProfile.swift
│   ├── DiningMenu.swift            // Cached scraped menu
│   └── Enums.swift
│
├── Services/
│   ├── BarcodeScanner.swift
│   ├── OpenFoodFactsAPI.swift
│   ├── AIVisionService.swift       // THE ONLY AI CALL
│   ├── DiningMenuService.swift     // fetches cached daily menus
│   ├── DiningOptimizer.swift       // constraint solver over menu
│   ├── MealRanker.swift            // pure algorithm, non-AI suggestions
│   └── FoodRepository.swift
│
├── Views/
│   ├── RootView.swift              // TabView
│   ├── Today/
│   │   ├── TodayView.swift
│   │   ├── MacroRingsView.swift
│   │   ├── MicroBarsView.swift
│   │   ├── MealSectionView.swift
│   │   └── QuickLogBar.swift
│   ├── Scanner/
│   │   ├── ScannerView.swift
│   │   └── ScanResultSheet.swift
│   ├── Vision/
│   │   ├── PhotoCaptureView.swift
│   │   └── AIEstimateSheet.swift
│   ├── Dining/
│   │   ├── DiningView.swift        // Browse dining hall menus
│   │   ├── OptimizerView.swift     // "Plan my day across dining halls"
│   │   └── OptimizerResultView.swift
│   ├── ManualEntry/
│   │   └── ManualFoodForm.swift
│   ├── History/
│   │   ├── HistoryView.swift
│   │   └── WeeklyReviewView.swift
│   ├── Gap/
│   │   └── CloseGapView.swift      // Non-AI "what should I eat"
│   └── Settings/
│       ├── SettingsView.swift
│       ├── TargetsEditor.swift
│       └── DietPreferencesEditor.swift
│
├── DesignSystem/
│   ├── Colors.swift
│   ├── Typography.swift
│   ├── Spacing.swift
│   └── Components/
│       ├── MacroRing.swift
│       ├── TargetBar.swift
│       ├── FoodRow.swift
│       └── PrimaryButton.swift
│
├── Utilities/
│   ├── ImageResizing.swift
│   ├── DateHelpers.swift
│   ├── Haptics.swift
│   └── SecretsLoader.swift
│
└── Tests/
    ├── OpenFoodFactsAPITests.swift
    ├── MealRankerTests.swift
    └── DiningOptimizerTests.swift
```

---

## 5. Data Model

### `Food` (`@Model`)

```
name: String
brand: String?
barcode: String?                    // nil for AI/manual/dining-hall
diningLocation: DiningLocation?     // if from a dining hall
servingSizeGrams: Double

// Macros per servingSizeGrams
calories, proteinG, carbsG, fatG: Double
fiberG, ironMg, vitaminDMcg, vitaminB12Mcg: Double

// Flags
source: FoodSource
isVegetarian: Bool
containsEggs: Bool
containsMushrooms: Bool
isFavorite: Bool

// Ranking bookkeeping
timesLogged: Int
lastLoggedAt: Date?
createdAt: Date
```

### `LogEntry` (`@Model`)

```
food: Food?
gramsEaten: Double
mealType: MealType
loggedAt: Date
photoData: Data?                    // if AI-logged
aiConfidence: Double?

// Computed: macros scale from food by (gramsEaten / food.servingSizeGrams)
```

### `UserProfile` (`@Model`, singleton)

```
calorieTarget, proteinTargetG, carbTargetG, fatTargetG: Double
fiberTargetG, ironTargetMg, vitaminDTargetMcg, vitaminB12TargetMcg: Double
dietGoal: DietGoal                  // .cut by default
isVegetarian: Bool                  // true by default
excludedIngredients: [String]       // ["eggs", "mushrooms"] by default
bodyWeightLb: Double?
```

### `DiningMenu` (`@Model`, cache)

```
location: DiningLocation            // cafe3, clarkKerr, crossroads, foothill
date: Date
mealPeriod: String                  // "brunch" / "dinner" / "allDay"
items: [DiningMenuItem]             // relationship
lastFetched: Date
```

### Enums

```
enum FoodSource      { case barcode, aiVision, manual, diningHall }
enum MealType        { case breakfast, lunch, dinner, snack }
enum DietGoal        { case cut, maintain, bulk }
enum DiningLocation  { case cafe3, clarkKerr, crossroads, foothill }
```

---

## 6. Services

### `OpenFoodFactsAPI` (actor)
Barcode → Food via free public API. No auth. Returns `Food` with `source = .barcode`. Auto-populates `containsEggs` / `containsMushrooms` from ingredients string.

### `AIVisionService` (actor)
The only AI call in the app. Uses Gemini 2.5 Flash with `responseMimeType: "application/json"` for structured output.

Prompt includes user's dietary exclusions as context:
> "User is vegetarian and excludes eggs and mushrooms. Identify food, estimate grams, estimate macros + fiber + iron + vitamin D + B12. If image contains excluded items, flag them. Return JSON matching schema: {...}"

Returns `EstimatedFood` with confidence score. User always confirms/edits in `AIEstimateSheet` before logging. On save, the `Food` is persisted locally — future encounters don't re-call AI.

### `DiningMenuService` (actor)
- `fetchMenus(forDate:) async throws -> [DiningMenu]`
- Hits the backend endpoint (TBD after DevTools inspection)
- Caches results locally in SwiftData
- Re-fetches if cache is older than 4 hours

### `DiningOptimizer` (service, not actor — pure computation)

Deterministic, no AI. Algorithm:

1. Load today's available menu items across specified dining halls
2. Filter out: non-vegetarian items, egg-containing, mushroom-containing, items without complete nutrition
3. Subtract already-logged calories/protein/etc. from targets → get remaining targets
4. Run optimization:
   - **Greedy (v1):** iteratively pick highest `protein / calorie` ratio item that still fits remaining budget; repeat until protein target hit or calorie budget exhausted
   - **LP (v1.5):** use Simplex solver if greedy misses the mark too often
5. Return ordered list: "At Crossroads dinner: 1.5 servings Halal Chicken Breast, 1 serving Navy Beans, 1 serving Squash Medley. Estimated: 620 cal, 58g protein, 12g fiber."

User can lock in the plan → creates pending log entries they confirm after eating.

### `MealRanker` (service)
Pure algorithm. Ranks foods by `timesLogged * exp(-daysSinceLastLogged / 14)`. Used by QuickLogBar and CloseGapView. Gets personalized over time without any learning model.

### `FoodRepository`
CRUD + aggregation over SwiftData. `dailyTotals(forDate:)`, `topFoods(limit:)`, `entries(forWeek:)`, etc.

---

## 7. Berkeley Dining Hall Integration

### Data pipeline (backend)

Cal Dining's menu page uses a WordPress plugin (`cal-dining`). Actual endpoint structure pending DevTools inspection. Possible scenarios:

1. **JSON endpoint exists** → direct fetch, minimal scraping
2. **HTML only** → parse with a scraper, store as JSON
3. **Per-item detail pages** → loop and fetch each
4. **No accessible nutrition** → email dietitian or drop feature

### Backend architecture (decided once data access confirmed)

Likely: **GitHub Action on cron**
- Runs at 5am daily
- Python scraper hits Cal Dining
- Outputs `menu-YYYY-MM-DD.json` committed to a public repo
- iOS app fetches raw GitHub URL
- Free, versioned, simple, zero infra
- Bonus: historical menu data for free

Alternative: **Cloudflare Worker** if we need more frequent updates or specific CORS headers.

### Data schema (per day, per hall)

```json
{
  "date": "2026-04-20",
  "location": "crossroads",
  "meals": {
    "brunch": {
      "start": "10:30",
      "end": "15:00",
      "items": [
        {
          "name": "Halal Chicken Breast",
          "category": "Center Plate",
          "serving_g": 113,
          "calories": 165,
          "protein_g": 31,
          "carbs_g": 0,
          "fat_g": 3.6,
          "fiber_g": 0,
          "iron_mg": 0.9,
          "vitamin_d_mcg": 0,
          "vitamin_b12_mcg": 0.3,
          "tags": ["halal"],
          "allergens": []
        }
      ]
    }
  }
}
```

Missing fields → `null`; optimizer skips those items or uses conservative estimates.

---

## 8. Key User Flows

### Flow A: Barcode log
Tap Scan → ScannerView → OFF lookup → ScanResultSheet → Log. No AI.

### Flow B: Photo / AI log
Tap Camera → capture → Gemini analyzes → AIEstimateSheet (confirm/edit with confidence indicator) → Log. The only AI call.

### Flow C: Quick-log
Top of TodayView shows top-5 most-logged foods. Tap → pre-filled sheet with last gram amount → Log. No AI.

### Flow D: Dining hall browse & log
Tap Dining tab → pick location + meal period → browse items → tap to log (pre-filled with standard serving size). No AI.

### Flow E: Dining hall optimizer
"Plan my dinner" button → DiningOptimizer runs locally → shows recommended combination → user accepts or adjusts → creates pending log entries. No AI.

### Flow F: Manual entry
Straight form. No AI.

### Flow G: Close the gap (non-AI)
"What should I eat?" button → shows remaining targets → scans your personal Food DB for items that would close the biggest gap → ranked by fit + recency → tap to log. No AI.

### Flow H: Weekly review
Sunday notification → WeeklyReviewView summary → free-text journal field.

---

## 9. Design System

### Philosophy
Native iOS. Not custom-designed; composed from Apple's toolkit with SF Rounded and restrained color. Should feel like a first-party app.

### Typography — SF Rounded throughout

```swift
extension Font {
    static let mLargeTitle  = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let mTitle       = Font.system(.title, design: .rounded, weight: .semibold)
    static let mTitle2      = Font.system(.title2, design: .rounded, weight: .semibold)
    static let mTitle3      = Font.system(.title3, design: .rounded, weight: .medium)
    static let mHeadline    = Font.system(.headline, design: .rounded, weight: .semibold)
    static let mBody        = Font.system(.body, design: .rounded)
    static let mCallout     = Font.system(.callout, design: .rounded)
    static let mSubheadline = Font.system(.subheadline, design: .rounded)
    static let mCaption     = Font.system(.caption, design: .rounded)
    
    // Monospaced for large numbers in macro displays
    static let mStatNumber  = Font.system(.title, design: .rounded, weight: .bold)
                                    .monospacedDigit()
}
```

Monospaced digits prevent "432" and "108" from shifting as values tick up during the day.

### Color — functional only

All semantic. System colors so dark/light mode comes free.

```swift
extension Color {
    // Background hierarchy (system-provided)
    static let mBgPrimary    = Color(.systemBackground)
    static let mBgSecondary  = Color(.secondarySystemBackground)
    static let mBgGrouped    = Color(.systemGroupedBackground)
    
    // Text hierarchy
    static let mTextPrimary   = Color(.label)
    static let mTextSecondary = Color(.secondaryLabel)
    static let mTextTertiary  = Color(.tertiaryLabel)
    
    // Functional state colors — the only "visible" colors
    static let mOnTarget    = Color.green   // hit target
    static let mApproaching = Color.orange  // 70-100% of target
    static let mUnder       = Color.gray    // < 70%, neutral
    static let mOver        = Color.red     // exceeded (calories/fat only)
    
    // Subtle accent for interactive elements
    static let mAccent      = Color.accentColor
}
```

Rule: a macro ring is gray when under target, orange as it approaches, green when hit. Red only when *calories* or fat exceed target (protein over target is fine).

### Spacing

```swift
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}
```

Use consistently. No arbitrary `padding(13)` calls.

### Components

- **Cards:** `RoundedRectangle(cornerRadius: 16)` with `.fill(Color.mBgSecondary)`
- **Rings:** stroke width 12, rounded line caps, 1.2s animation on value change
- **Bars:** height 8, capsule shape, animated fill
- **Rows:** 56pt minimum tap target, trailing chevron if navigable
- **Sheets:** `.presentationDetents([.medium, .large])` for confirm/edit flows

### Motion

- Default: `.spring(response: 0.4, dampingFraction: 0.8)` for UI transitions
- Progress rings: `.easeOut(duration: 1.2)` when value updates
- No bounce, no flashy effects. Subtle and native.

### Haptics

Every meaningful action gets a haptic:
- `.impact(.light)` on every tap that logs a food
- `.notification(.success)` when daily macro target is first hit
- `.impact(.soft)` on sheet dismissal
- `.selection` on segmented control changes

### Empty states

Every list view has a proper empty state — SF Symbol + short friendly line + primary action button.

### Loading states

Skeletons > spinners for lists. `RoundedRectangle` with shimmer for predictable layouts. Spinner only for full-screen API waits (Gemini analysis, dining menu fetch).

---

## 10. Personalization Logic

All non-AI:

- **Exclusion enforcement**: `UserProfile.excludedIngredients` default `["eggs", "mushrooms"]`. Barcode + dining items with matching ingredient strings show a soft warning (override-able). Optimizer hard-filters.
- **Food ranking**: `score = timesLogged * exp(-daysSinceLastLogged / 14)`. Surfaces foods you actually eat.
- **Target scaling**: If `bodyWeightLb` set, `proteinTargetG = 1.0 * bodyWeightLb` (cut) or `0.9 *` (maintain). Editable.

---

## 11. Secrets Management

1. `Secrets.xcconfig` at project root with `GEMINI_API_KEY = ...`
2. Target Build Settings → Configurations → use xcconfig for Debug + Release
3. `Info.plist` row: `GEMINI_API_KEY` → `$(GEMINI_API_KEY)`
4. `.gitignore` includes `Secrets.xcconfig`
5. Commit `Secrets.xcconfig.example` as template

---

## 12. 7-Day Reinstall Reality

SwiftData survives app *binary* replacement. Before 7-day expiry: plug in phone, hit Run — Xcode replaces binary, container keeps data. Only uninstalling the app loses data (v1 local-only).

Post-v1: CloudKit migration for survival across uninstalls and multi-device.

---

## 13. Build Order

### Phase 1 — Foundation (~3-4 hrs)
1. Xcode project setup (SwiftUI, SwiftData, iOS 17)
2. `Models/` — all `@Model` classes + enums
3. `DesignSystem/` — Colors, Typography, Spacing files
4. `CLAUDE.md` — project conventions
5. `MacroScanApp.swift` — `ModelContainer` setup
6. `RootView` with `TabView` skeleton (Today / Dining / History / Settings)
7. `UserProfile` singleton created on first launch with defaults
8. **Verify:** app builds, tabs render, SF Rounded visible everywhere

### Phase 2 — Barcode path (~3 hrs)
1. `BarcodeScanner.swift` (AVFoundation)
2. Camera permission flow
3. `OpenFoodFactsAPI.swift`
4. `ScannerView` + `ScanResultSheet`
5. `FoodRepository.save(logEntry:)`
6. TodayView list of today's entries
7. **Verify:** scan a real product, appears in TodayView

### Phase 3 — Manual + Today polish (~2-3 hrs)
1. `ManualFoodForm`
2. `MacroRingsView`, `MicroBarsView` with design tokens
3. `QuickLogBar` with `MealRanker`
4. Meal sections in TodayView
5. Haptics on log actions
6. **Verify:** fully functional Today tab without AI

### Phase 4 — AI vision (~3 hrs)
1. `Secrets.xcconfig` setup
2. `AIVisionService.swift` with dietary context in prompt
3. `PhotoCaptureView` + `AIEstimateSheet`
4. Confidence indicator UI (color + icon)
5. **Verify:** photograph meal, get estimate, confirm, log

### Phase 5 — History + Settings (~2-3 hrs)
1. `HistoryView` with Swift Charts
2. `SettingsView`, `TargetsEditor`, `DietPreferencesEditor`
3. `WeeklyReviewView`
4. **Verify:** full week of logs rendered; can edit targets

### Phase 6 — Dining hall (~4-6 hrs, gated on data verification)
1. Decide backend (GitHub Action vs. on-device vs. Worker)
2. Build scraper
3. `DiningMenuService` client
4. `DiningView` for browsing menus
5. `DiningOptimizer` with greedy algorithm
6. `OptimizerView` + `OptimizerResultView`
7. **Verify:** opens today's real Crossroads dinner menu; optimizer produces valid plan

### Phase 7 — Close the gap (~1-2 hrs)
1. `CloseGapView` using `MealRanker` over personal food DB
2. **Verify:** shows relevant "what to eat" suggestions from known foods

### Phase 8 — Visual polish (~2-3 hrs)
Dedicated pass. Empty states, loading skeletons, transitions, spacing audit, haptic coverage, App Icon, launch screen.

**Total: ~20-27 hrs** depending on how clean the Cal Dining data access turns out.

---

## 14. Open Decisions

- **Dining hall data access**: pending DevTools inspection (user action)
- **Backend for dining scraper**: decide once data access is confirmed
- **AI fallback if Gemini fails**: v1 shows error + offer manual entry. No secondary AI provider in v1.
- **Copy yesterday's meals**: deferred to v1.1 — high value, low effort
- **Weight tracking**: field exists on UserProfile, UI deferred

---

## 15. Claude Code Conventions (for `CLAUDE.md`)

- SwiftData `@Model` classes passed via `@Environment(\.modelContext)`
- Network clients are `actor`s — awaited from `@MainActor` views
- Use `Task { @MainActor in ... }` to bridge async → SwiftUI state
- API response types stay `private` inside their service files
- Prefer `.sheet(item:)` over `.sheet(isPresented:)` for edit flows
- Swift Charts for all history visualizations
- Commit after each phase's verify step passes
- Never hardcode secrets; always `Bundle.main.object(forInfoDictionaryKey:)`
- Every new view uses DesignSystem tokens (Colors, Typography, Spacing). No inline `Color.blue` or `Font.title`.
- Every user action that logs something triggers a haptic
- Every list has an empty state with SF Symbol + message + action button
- AI is called only from `AIVisionService`. Do not introduce AI calls in other services.
