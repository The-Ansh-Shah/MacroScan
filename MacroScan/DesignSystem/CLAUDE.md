# DesignSystem — shared visual tokens & reusable components

Native-iOS aesthetic: all type is SF Rounded, layout uses a fixed spacing scale, and the only "visible" (non-system) color is functional — green/orange/gray/red signal progress toward macro targets. Backgrounds and text use system semantic colors so light/dark mode is automatic.

## Tokens
- **Fonts** (`Typography.swift`): `.mLargeTitle` `.mTitle` `.mTitle2` `.mTitle3` `.mHeadline` `.mBody` `.mCallout` `.mSubheadline` `.mCaption`; monospaced-digit stat fonts `.mStatNumber` `.mStatNumberLarge`. All are `Font.system(..., design: .rounded)`.
- **Colors** (`Colors.swift`): bg hierarchy `.mBgPrimary` `.mBgSecondary` `.mBgGrouped`; text hierarchy `.mTextPrimary` `.mTextSecondary` `.mTextTertiary`; functional state `.mOnTarget` (green, hit target) `.mApproaching` (orange, 70–100%) `.mUnder` (gray, <70%) `.mOver` (red, exceeded — calories/fat only); `.mAccent` (accentColor, interactive). Bg/text wrapped in `#if canImport(UIKit)` (UIKit colors) vs AppKit fallback. Use `Color.targetColor(ratio:isOverBad:)` to pick state color from progress.
- **Spacing** (`Spacing.swift`): `Spacing.xs`=4, `.sm`=8, `.md`=16, `.lg`=24, `.xl`=32, `.xxl`=48. Also `DesignConstants`: `cardCornerRadius`=16, `ringStrokeWidth`=12, `barHeight`=8, `minTapTarget`=56, `ringAnimation`, `springAnimation`.

## Components/
- `MacroRing.swift` — circular progress ring for a macro (label/current/target/unit/isOverBad), color via `targetColor`, caps fill at 100%.
- `TargetBar.swift` — horizontal capsule progress bar, same target-color logic, for micros/secondary stats.
- `FoodRow.swift` — list row: name (+optional verified seal), detail, calories & protein, optional chevron; min height = minTapTarget.
- `AmountPicker.swift` — segmented Servings/Grams input that keeps the two units in sync; exposes `gramsEaten`/`servingsEaten`.
- `PrimaryButton.swift` — full-width accent CTA (optional icon); also defines `EmptyStateView` (symbol + message + optional button).

## Rule
- Every view MUST use these tokens — no inline `Color.blue`, `Font.title`, or magic padding numbers.
