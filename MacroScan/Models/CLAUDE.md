# Models — SwiftData @Model layer

SwiftData persistence layer. Each `@Model final class` is a stored entity; macro math (scaling, summing) lives on the models themselves via the `ScaledMacros` value type. Two files here are NOT @Model: `Enums.swift` (shared enums) and `BalanceFlag.swift` (transient UI struct).

## Files
- `Food.swift` — food entity; macros stored **per `servingSizeGrams`**. `macros(forGrams:)` scales by `grams/servingSizeGrams` and returns `ScaledMacros`. Also defines `struct ScaledMacros` (`+`, `.zero`).
- `LogEntry.swift` — a logged item; `food` is optional (nil ⇒ quick-add via `quickAdd*` fields, see `isQuickAdd`). `scaledMacros` delegates to `food.macros(forGrams:)` or builds from quick-add fields.
- `Recipe.swift` — recipe + `RecipeIngredient` (@Model). `perServingMacros` sums ingredient macros / `totalServings`. Cascade @Relationship to ingredients.
- `UserProfile.swift` — singleton holding macro/micro targets + body/diet prefs. Optional `currentGoal: WeightGoal`. Has AI/FatSecret telemetry counters.
- `BodyMeasurement.swift` — point-in-time body snapshot (weight, bf%, tape measures). Charted by `BodyCompositionView`.
- `WeightGoal.swift` — active/past weight or bf% goal with start+target.
- `WaterEntry.swift` — single water log (ml).
- `Enums.swift` — `FoodSource`, `MealType`, `DietGoal`, `BiologicalSex`, `ActivityLevel` (with TDEE `multiplier`s). All `String, Codable, CaseIterable`.
- `BalanceFlag.swift` — NOT persisted; UI insight struct generated per-day by `FoodRepository.balanceFlags(...)`, rendered in `InsightsCard`.

## Conventions & gotchas
- SwiftData can't persist enums on @Model classes: stored as `...Raw: String` with a computed typed accessor (e.g. `source`/`sourceRaw`, `mealType`, `dietGoal`, `biologicalSex`, `activityLevel`, `bodyFatSource`). Getters fall back to a default on bad raw values. Enums *inside non-@Model types* (BalanceFlag) are kept as real enums.
- **UserProfile is a singleton by convention, NOT schema** — created/guaranteed by `RootView.ensureUserProfile()` (insert if `profiles.first == nil`). Always read via `profiles.first`.
- Current weight: prefer `FoodRepository.currentWeightLb(profile:)` (latest BodyMeasurement, falls back to `profile.bodyWeightLb`), not `bodyWeightLb` directly.
- New non-optional properties MUST have an **inline default** (`= ...`) for SwiftData lightweight migration (e.g. `Food.ingredients`, `userVerified`, `UserProfile.activityLevelRaw`/`dailyStepTarget`/`dailyWaterTargetMl`). Same for `exportID: UUID = UUID()` present on most models.
- `exportID` = stable UUID for JSON backup dedup (`DataExportService`).
- Relationships: `Recipe.ingredients` ↔ `RecipeIngredient.recipe` (cascade delete); `LogEntry.food`, `RecipeIngredient.food`, `UserProfile.currentGoal` are optional refs.
- Macros default in `UserProfile.init`: 1800 cal / 160P / 180C / 55F, vegetarian, excludes eggs+mushrooms.

## Related
- Registered in the ModelContainer schema in `../MacroScanApp.swift` (Food, LogEntry, UserProfile, BodyMeasurement, WeightGoal, Recipe, RecipeIngredient, WaterEntry).
- Queried/mutated mainly through `../Services/FoodRepository.swift`, `../Services/BodyCompositionService.swift`, `../Services/DataExportService.swift`.
