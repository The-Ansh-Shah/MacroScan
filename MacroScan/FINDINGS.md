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
- **@Bindable for @Model bindings:** You can't use `$profile` on a computed `UserProfile?` property. Extract a child view that takes the unwrapped `@Model` object and use `@Bindable var profile: UserProfile` on it. Bind to raw `String` properties (e.g. `$profile.dietGoalRaw`) for Pickers on enum-backed stored properties.
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

## Completed Implementation Notes

### Phase 5 — History + Settings
- `HistoryView` uses `import Charts` with `BarMark` + `RuleMark` for targets
- `DaySummary` is a private struct in HistoryView — computes last7Days from allEntries
- `SettingsView` uses `Binding` on `@Query`-fetched profile — SwiftData auto-persists changes
- `ExclusionsEditor` is in SettingsView.swift — separate struct, NavigationLink push
- `WeeklyReviewView` has free-text journal field (State only — not persisted yet)

### Phase 6 — Dining Hall
- `DiningMenuService` is an actor with `@MainActor` fetch method (needs modelContext)
- Placeholder base URL — swap to real GitHub raw URL once scraper is live
- `DiningOptimizer.optimize()` is a pure static function — no actor needed
- Greedy algo caps at 2.0 servings per item, rounds to 0.5 increments
- `OptimizerView` "Accept Plan" creates Food + LogEntry for each planned item

### Phase 7 — Close the Gap
- `CloseGapView` reuses `ScanResultSheet` for logging selected suggestions
- `MealRanker.closeGapSuggestions` scores: `(proteinFill * 3 + fiberFill) * (1 + recencyBoost)`
- Foods exceeding calorie gap by >50 cal are filtered out

### Phase 8 — Polish
- `ShimmerModifier` uses `LinearGradient` overlay with repeating animation
- `SkeletonRow` is a pre-built loading placeholder matching FoodRow dimensions
- All loading states use skeleton rows (DiningView) or ProgressView (scanner, AI)
- Transitions: scanner uses `.scale.combined(with: .opacity)`

### Remaining Work (future)
- **Deployment target**: Must be set to iOS 18.0 in Xcode project settings (can't edit pbxproj from code)
- **Dining data pipeline**: Replace placeholder URL in DiningMenuService once scraper is built
- **Weekly journal persistence**: WeeklyReviewView journal text is @State only — not saved to SwiftData
- **App Icon + Launch Screen**: Not yet created
