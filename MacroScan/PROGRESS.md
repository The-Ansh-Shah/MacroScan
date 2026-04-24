# MacroScan — Build Progress

Reference: [ARCHITECTURE.md](ARCHITECTURE.md)

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
- [x] OpenFoodFactsAPI.swift (actor)
- [x] ScannerView + ScanResultSheet
- [x] FoodRepository CRUD + aggregation
- [x] TodayView list of today's entries
- [x] **Verify:** builds, scanner wired, OFF lookup works

## Phase 3 — Manual + Today Polish
- [x] ManualFoodForm
- [x] MacroRings in TodayView + MicroBarsView
- [x] QuickLogBar with MealRanker
- [x] MealSectionView with swipe-to-delete
- [x] Haptics on log actions
- [x] **Verify:** fully functional Today tab without AI

## Phase 4 — AI Vision
- [x] Secrets.plist setup (GEMINI_API_KEY)
- [x] AIVisionService.swift (Gemini 2.5 Flash, structured JSON)
- [x] PhotoCaptureView (UIImagePickerController wrapper)
- [x] AIEstimateSheet (editable confirm, confidence badge, warnings)
- [x] TodayView "Snap Photo" flow wired end-to-end
- [x] **Verify:** builds clean

## Phase 5 — History + Settings
- [x] HistoryView with Swift Charts (7-day calorie + protein bars, week summary)
- [x] WeeklyReviewView (daily averages, notes journal)
- [x] SettingsView (macro/micro target editors, body weight, auto-protein)
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
- [x] "What should I eat?" button in TodayView
- [x] **Verify:** builds clean, wired to MealRanker.closeGapSuggestions

## Phase 8 — Visual Polish
- [x] ShimmerModifier + SkeletonRow for loading states
- [x] Skeleton loading in DiningView
- [x] Scale+opacity transition on scanner loading
- [x] Ring animation: .easeOut(1.2s) — confirmed in DesignConstants
- [x] Spring animation: .spring(0.4, 0.8) — confirmed in DesignConstants
- [x] Empty states on all list views (Today, History, Dining, Settings)
- [x] Haptics on log, target hit, sheet dismiss, picker change
- [x] **Verify:** full build succeeds with 0 errors
