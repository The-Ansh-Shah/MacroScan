# MacroScan

Personal iOS food-logging app (single user, not App Store). Barcode scanning, one AI photo-estimation call, manual/natural-language entry, recipes, macro+micro tracking, body-composition & goal planning, water, history. Cutting-focused with configurable, goal-aware targets. Native-iOS aesthetic (SF Rounded, functional color only).

> The dining-hall feature described in older docs was **removed** (iteration 5). No dining code remains; RootView runs a one-time dining→manual data migration.

## Stack
- Swift / SwiftUI / **SwiftData** (local-only persistence, no CloudKit yet)
- Min deployment: **iOS 18** (must be set in Xcode project — can't be edited from code)
- Also compiles for **macOS** → all UIKit usage needs `#if canImport(UIKit)` guards
- Swift concurrency (async/await + actors). **No Combine.** Use `@Observable` (not `ObservableObject`), `@State` (not `@StateObject`)
- Zero external packages. Charts = built-in Swift Charts.

## Layout (each dir has its own CLAUDE.md — read it before working there)
- `Models/` — SwiftData `@Model` entities + shared enums. Macro math lives on the models (`ScaledMacros`).
- `Services/` — networking (actors), persistence access (`FoodRepository`, @MainActor), pure logic (BodyComposition, MealRanker).
- `Views/` — SwiftUI screens; `RootView` is the 4-tab entry (Today / History / Me / Settings).
- `DesignSystem/` — mandatory `Color.m*` / `Font.m*` / `Spacing.*` tokens + reusable components.
- `Utilities/` — small UIKit-guarded helpers (Haptics, SecretsLoader, image resize, date/keyboard).
- `MacroScanApp.swift` — `@main`; builds the shared `ModelContainer` (wipes & retries the store on migration failure — pre-release, no durable data).

## Conventions
- **DesignSystem tokens are required** in every view — never inline `Color.blue`, `Font.title`, or magic padding numbers.
- **One AI call, ever**: only `Services/AIVisionService.swift` (Gemini) talks to an LLM. Do not add others.
- Network clients are `actor`s; SwiftData-touching services are `@MainActor`; pure math is a static `enum`/`struct`.
- SwiftData can't store enums → store `...Raw: String` + computed typed accessor. New non-optional `@Model` props need an inline default for lightweight migration.
- `UserProfile` is a singleton **by convention** (`RootView.ensureUserProfile`), read via `profiles.first`. Canonical current weight = `FoodRepository.currentWeightLb(profile:)`.
- Prefer `.sheet(item:)` over multiple `isPresented` bools. Fire a `Haptics.*` on every log/delete. Every list has an `EmptyStateView`.
- Secrets via `SecretsLoader` only (reads gitignored `Secrets.plist`) — never hardcode keys.

## Platform / Swift 6 gotchas
- Guard all UIKit APIs (`keyboardType`, `.navigationBarTitleDisplayMode`, `UIColor`/`UIImage`, camera/photo views) with `#if canImport(UIKit)`. `UIScreen.main` is deprecated → use view bounds.
- Use `await AVCaptureDevice.requestAccess(for:)` (async form).
- Private `Decodable` structs inside actors may emit Swift 6 isolation warnings — harmless in Swift 5 mode; `nonisolated` decode helpers reduce them.

## Build / data reality
- Local-only: SwiftData survives binary replacement but not app uninstall. `DataExportService` provides JSON backup/restore (dedup by `exportID`) to survive uninstalls.
- Not yet done: weekly-review journal persistence, App Icon / launch screen, CloudKit sync.
