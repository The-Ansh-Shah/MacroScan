# Services — business logic, networking, persistence access

Stateless/logic layer between SwiftData models and SwiftUI views. Network clients are `actor`s; SwiftData-touching services are `@MainActor`; pure math is a plain `enum`/`struct` of statics. Each networking file keeps its own `private` Decodable response types at the bottom and maps them to the shared `Food` model.

## Files
- `AIVisionService.swift` — `actor`. THE ONLY LLM/AI call in the app: Gemini 2.5 Flash food-photo → `EstimatedFood` (macros+micros+flags). Retries on 429/503/overload with 1s/3s/8s backoff (3 attempts). JSON parsed manually via `JSONSerialization`, then `private AIFoodResult` Decodable.
- `OpenFoodFactsAPI.swift` — `actor`, no auth. `search(query:)` → `[Food]` (source `.barcode`). Infers vegetarian/eggs/mushrooms from ingredients text; `DoubleOrString` decoder tolerates numeric-or-string nutrient fields.
- `FatSecretAPI.swift` — `actor`. Third search source (restaurant/branded). search, foodDetail, autocomplete, barcodeLookup → `Food` (source `.fatSecret`). Routes ALL calls through a Cloudflare Worker proxy (params as GET query items, `X-Client-Secret` header); ~5000 calls/day.
- `FoodSearchService.swift` — `@MainActor struct`. Aggregator: runs local SwiftData + OFF + FatSecret in parallel (`async let`), dedups by lowercased name, ranks favorites→frequent→FatSecret→OFF→occasional. Tracks/suppresses FatSecret daily call count on `UserProfile`.
- `FoodRepository.swift` — `@MainActor class`. Central CRUD/aggregation over SwiftData (Food, LogEntry, Recipe, WaterEntry, BodyMeasurement, UserProfile): logging, quick-add, copy meals, daily/weekly totals, adherence, `balanceFlags`, water. `currentWeightLb()` is the canonical "current weight" (latest measurement > profile fallback).
- `HealthKitService.swift` — `actor` singleton (`.shared`); `#if canImport(HealthKit)` with a no-op stub otherwise. Bidirectional: READS weight/bodyfat/active+basal energy/steps/water; WRITES nutrition (cal/protein/carbs/fat/fiber), water, body measurements (weight+bodyfat).
- `BodyCompositionService.swift` — pure `enum`, no AI/persistence. Mifflin-St Jeor BMR→TDEE, dynamic TDEE from HK energy, Navy-method body fat, and `computeDeficitPlan` with hard safety rails (calorie floor, weekly-loss cap, protein floor, body-fat floor → `SafetyWarning`/`DeficitPlan`).
- `MealRanker.swift` — pure `struct`, no AI. `rank` = recency-weighted score `timesLogged * exp(-daysSince/14)`; `closeGapSuggestions` picks foods filling protein/fiber gap within calorie budget.
- `BarcodeScanner.swift` — `@MainActor @Observable class` (UIKit only). AVFoundation camera scanner; `start()` handles auth→setup→run in one call; publishes `scannedCode`.
- `DataExportService.swift` — `@MainActor struct`. Full JSON export/import (version 1) of all models via `*DTO` types; import dedups by `exportID`, rebuilds Food refs through a `foodMap`. Returns `ImportResult` summary.

## Conventions & gotchas
- Actors: AIVisionService, OpenFoodFactsAPI, FatSecretAPI, HealthKitService. @MainActor: FoodRepository, FoodSearchService, DataExportService, BarcodeScanner. Pure statics: BodyCompositionService, MealRanker.
- Single-AI-call rule: AIVisionService is the *only* Gemini/LLM caller — do not add other LLM calls.
- Secrets: `SecretsLoader` is a plain `Sendable` enum reading Secrets.plist (GEMINI_API_KEY, FATSECRET_PROXY_URL, FATSECRET_CLIENT_SECRET). Actors read it directly; AIVisionService wraps the read in `await MainActor.run` (legacy — not required since SecretsLoader isn't MainActor-isolated).
- Threading bridge: HealthKitService (actor) hops to `@MainActor.run` to read SwiftData model props (entry/measurement) before writing HK samples. FoodRepository fires `Task { try? await HealthKitService.shared.write… }` after logging food/water.
- Each networking file holds its `private` Decodable response structs + mapping (`mapToFood` etc.) at file bottom; nutrients normalized to the `Food` model.
- Three food sources are NOT independent: OFF + FatSecret + local are all merged by FoodSearchService.search. Barcode flow uses OFF `lookup` / FatSecret `barcodeLookup` directly.

## Related
- `../Models/` — Food, LogEntry, Recipe, WaterEntry, BodyMeasurement, UserProfile, WeightGoal, ScaledMacros, BalanceFlag, SafetyWarning enums consumed here.
- `../Utilities/SecretsLoader.swift` — API key/proxy loading; `Haptics` (BarcodeScanner).
- Views: Today/search/scan/body-composition/settings views consume FoodRepository, FoodSearchService, BarcodeScanner, DataExportService.
