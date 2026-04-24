# MacroScan — Build Findings & Notes

Quick-reference file for debugging patterns and implementation shortcuts.

---

## Platform Quirks

- **Project builds for macOS too** (not iOS-only). Every UIKit usage needs `#if canImport(UIKit)` guards:
  - `UIColor` system colors (`.systemBackground`, `.label`) → use platform-conditional `Color` extensions (see `Colors.swift`)
  - `.keyboardType()`, `.navigationBarTitleDisplayMode()` → wrap in `#if canImport(UIKit)`
  - `UIImage`, `UIImagePickerController`, `UIGraphicsImageRenderer` → entire files wrapped
  - `UIScreen.main` is deprecated in iOS 26 — use `uiView.bounds` instead
  - `UIApplication.openSettingsURLString` — only available under UIKit

## Concurrency / Swift 6

- **No Combine.** Architecture mandates async/await. Use `@Observable` (iOS 17+) instead of `ObservableObject`/`@Published`. In SwiftUI, use `@State` instead of `@StateObject`.
- **Actors + Decodable:** Private `Decodable` structs used inside actors get inferred as `@MainActor`-isolated, causing "cannot be used in actor-isolated context" warnings. These are Swift 6 warnings only (harmless in Swift 5 mode). Marking structs `Sendable` helps but doesn't fully silence. Using `nonisolated static func` for decode helpers reduces warnings.
- **`SecretsLoader`** is `Sendable` enum with `nonisolated(unsafe) static let` for its cache. Actors can read `SecretsLoader.geminiAPIKey` via `await MainActor.run { ... }`.
- **`AVCaptureDevice.requestAccess`** — use the async version (`await AVCaptureDevice.requestAccess(for:)`) instead of the callback version to avoid Swift 6 `self` capture warnings.

## SwiftData Patterns

- **Enums in @Model:** SwiftData can't store raw enums directly. Store as `String` (e.g. `mealTypeRaw: String`) with a computed property for the typed enum. See `Food.sourceRaw`, `LogEntry.mealTypeRaw`, `DiningMenu.locationRaw`.
- **@Query with dynamic dates:** `#Predicate` can't call computed properties like `Date().startOfDay`. Instead, query all and filter in a computed property: `allEntries.filter { $0.loggedAt >= startOfToday }`.
- **@Model classes are already Identifiable** via `PersistentModel`. Don't add `extension Food: Identifiable {}` — it causes "does not conform to PersistentModel" errors.
- **FoodRepository** takes `ModelContext` in init, created inline: `FoodRepository(modelContext: modelContext)`. Not a singleton.

## Design System Tokens

- **Fonts:** Always `Font.mBody`, `.mHeadline`, `.mTitle3`, etc. — never raw `Font.title`.
- **Colors:** Always `Color.mTextPrimary`, `.mBgSecondary`, `.mAccent`, `.mOnTarget`, `.mApproaching`, `.mUnder`, `.mOver` — never raw `Color.blue`.
- **Spacing:** Always `Spacing.xs/sm/md/lg/xl/xxl` — never `padding(13)`.
- **Cards:** `RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)` + `.fill(Color.mBgSecondary)`.
- **Min tap target:** `DesignConstants.minTapTarget` (56pt).

## File-Level Constants

- `DesignConstants.cardCornerRadius` = 16
- `DesignConstants.minTapTarget` = 56
- `DesignConstants.ringStrokeWidth` = 12

## Key Type Signatures

```
Food.macros(forGrams:) -> ScaledMacros
LogEntry.scaledMacros -> ScaledMacros  (computed, delegates to food)
ScaledMacros: calories, proteinG, carbsG, fatG, fiberG, ironMg, vitaminDMcg, vitaminB12Mcg
ScaledMacros.zero, ScaledMacros + ScaledMacros
MealRanker.topFoods(from:limit:) -> [Food]  (score = timesLogged * exp(-daysSince/14))
FoodRepository(modelContext:) — not a singleton, create per-use
```

## Upcoming Phase Notes

### Phase 5 — History + Settings
- `HistoryView` needs `import Charts` for Swift Charts
- `SettingsView` currently a placeholder stub — needs TargetsEditor + DietPreferencesEditor
- `WeeklyReviewView` not yet created — needs a new file
- `FoodRepository.entriesForWeek(startingFrom:)` already exists for chart data

### Phase 6 — Dining Hall
- `DiningMenu` model exists, `DiningMenuItem` is a `Codable` struct stored in array
- `DiningMenuService` and `DiningOptimizer` files don't exist yet
- `OptimizerView` and `OptimizerResultView` files don't exist yet
- `DiningView` currently a placeholder stub

### Phase 7 — Close the Gap
- `CloseGapView` doesn't exist yet
- Needs: remaining targets (profile targets - daily totals), filter foods by what closes biggest gap
- `MealRanker.topFoods` already ranks by recency+frequency — extend for gap-closing

### Phase 8 — Polish
- Empty states: `EmptyStateView` component exists, ensure every list uses it
- Loading skeletons: not built yet, need shimmer modifier
- Transitions: `.spring(response: 0.4, dampingFraction: 0.8)` per architecture
- Ring animation: `.easeOut(duration: 1.2)` — verify MacroRing uses this
