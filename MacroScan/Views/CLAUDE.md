# Views — SwiftUI screens & sheets

`RootView` is the app entry: a 4-tab `TabView`. It also seeds a singleton `UserProfile` on appear (`ensureUserProfile`), runs a dining-hall→manual data migration, and presents `ProfileSetupView` onboarding when the profile lacks height/age. Most screens read the profile via `@Query private var profiles` and use `profiles.first`.

## Tab / navigation map
- Today → `TodayTabView` (owns selected date + `DateScroller` over a bound `DayView`)
- History → `HistoryView` (segmented Days / Trends; rows push read-only `DayView`)
- Me → `MeView` (profile, active goal, quick actions, measurements, targets)
- Settings → `SettingsView`
- Onboarding `ProfileSetupView` is presented as a sheet from RootView, not a tab.

## Subdirectories
### Today/ — Today tab: date scroller, day totals, meals, water, insights
- `TodayTabView.swift` — Today root; `NavigationStack` + `DateScroller` + bound `DayView`.
- `DateScroller.swift` — Horizontal 60-day strip with target-hit dots; today rightmost.
- `DayView.swift` — Per-day entries/totals/insights; hosts all log-entry sheets + add menu; `isTodayTab` gates Today-only affordances.
- `MealSectionView.swift` — One meal-type card; edit/delete via contextMenu + ellipsis confirmationDialog (no swipe; not a List).
- `MicroBarsView.swift` — Fiber/iron/vit-D/B12 progress bars vs profile targets.
- `WaterCard.swift` — Water oz vs target with +8/+16/custom quick-adds; taps open WaterDetailSheet.
- `QuickLogBar.swift` — Top foods/recipes (MealRanker) for one-tap re-log.
- `InsightsCard.swift` — Collapsible `BalanceFlag` insights with deep-links.

### Body/ — body composition, TDEE, goals (reached via Me/Settings)
- `BodyCompositionView.swift` — Measurement list + weight/BF charts, TDEE/goal summary, Health import banners.
- `LogMeasurementSheet.swift` — Log weight/circumferences; Navy body-fat estimate.
- `ProfileEditorSheet.swift` — Edit height/age/sex/activity (`@Bindable` profile).
- `GoalPlannerView.swift` — Target weight/BF + date → DeficitPlan with safety warnings; applies targets. Holds shared `GoalPlanning.disclaimer`.
- `GoalProgressView.swift` — Actual vs projected progress chart for active WeightGoal.

### Scanner/ — barcode scanning (UIKit-only)
- `ScannerView.swift` — Camera barcode scan → FatSecret/OFF lookup; `#if canImport(UIKit)`.
- `ScanResultSheet.swift` — Confirm/edit a looked-up Food and log it; ingredient substitution + nutrition editing.

### Vision/ — AI meal-photo estimation (UIKit-only)
- `PhotoCaptureView.swift` — `UIViewControllerRepresentable` camera/library picker.
- `AIEstimateSheet.swift` — AI vision estimate with analyzing/ready/errored phases; editable + logs.

### Search/ — food text search
- `SearchView.swift` — Debounced (250ms) local+FatSecret+OFF search; tap result → `ScanResultSheet`.

### ManualEntry/ — manual & NL logging sheets
- `ManualFoodForm.swift` — Create a Food (per-serving macros) and log it.
- `QuickAddSheet.swift` — Calories-only quick log (macros optional); reused for editing via `editingEntry`.
- `EditLogEntrySheet.swift` — Edit existing entry's amount/meal/notes (not the Food).
- `AIFallbackSheet.swift` — Manual form shown when AI vision fails; preserves photo (UIKit-only).

### Recipes/ — multi-food recipes
- `RecipesView.swift` — Recipe list (favorites first, searchable); swipe to delete.
- `RecipeBuilderView.swift` — Build/edit recipe from foods + grams; computes per-serving macros.
- `RecipeDetailView.swift` — Recipe detail; log/edit/delete.

### History/ — past days & trends
- `HistoryView.swift` — Days/Trends segmented control; rows push read-only `DayView`.
- `WeeklyReviewView.swift` — Past-7-day totals, highlights, journal note.

### Me/ — `MeView.swift` — Profile hub: header, active goal, quick actions, recent measurements, calorie/macro/micro targets, stale-measurement prompt.
### Gap/ — `CloseGapView.swift` — Non-AI "what to eat": remaining targets + MealRanker suggestions from personal DB.
### Settings/ — `SettingsView.swift` — Settings form (`@Bindable` via inner SettingsFormView): targets, export/import, counts.
### Onboarding/ — `ProfileSetupView.swift` — First-launch profile setup (skippable); enables BMR/TDEE.

## Conventions & gotchas
- DesignSystem tokens are mandatory: colors `Color.mAccent / .mTextPrimary / .mBgSecondary / .mOnTarget / .mApproaching`, fonts `.mBody / .mHeadline / .mCaption`, spacing `Spacing.xs/sm/md`, `DesignConstants.cardCornerRadius`. No inline `Color.blue` / `Font.title`.
- Prefer `.sheet(item:)` with `Identifiable` state (e.g. `editingEntry`, `CapturedPhoto`) over multiple `isPresented` bools.
- Fire `Haptics.logFood()` on log, `Haptics.deleted()` on delete, `Haptics.selectionChanged()`, `Haptics.sheetDismissed()` on cancel.
- Empty states use `EmptyStateView(symbol:message:[buttonTitle:action:])`.
- All data via `@Environment(\.modelContext)` and `@Query`; profile is a singleton (`profiles.first`); mutate via `FoodRepository`.
- Guard UIKit-only APIs with `#if canImport(UIKit)`: `keyboardType`, `.navigationBarTitleDisplayMode(.inline)`, camera/photo views.
- Add `.keyboardDoneButton()` to any keyboard-driven form/sheet.
- Today targets are goal-aware (profile targets reflect active WeightGoal/TDEE).
- Logging supports servings-or-grams: shared `AmountPicker` with `useServings` toggle; convert via `food.servingSizeGrams`.
