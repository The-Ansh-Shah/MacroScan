# Utilities — small cross-cutting helpers

Stateless helpers. Most are UIKit-only and wrapped in `#if canImport(UIKit)` (the project also compiles for macOS).

## Files
- `DateHelpers.swift` — `Date` extensions (`startOfDay`, day math) used for per-day bucketing of logs.
- `Haptics.swift` — `enum Haptics` (UIKit-only). Call `Haptics.logFood()` / `.deleted()` / `.selectionChanged()` / `.sheetDismissed()` from views; no-op off-UIKit.
- `ImageResizing.swift` — `enum ImageResizing` (UIKit-only): downscale + JPEG-encode a `UIImage` before sending to AI vision.
- `KeyboardHelpers.swift` — `View.hideKeyboard()` + `.keyboardDoneButton()` toolbar modifier (UIKit-only). Add the Done button to any keyboard-driven form.
- `SecretsLoader.swift` — `enum SecretsLoader: Sendable`. Reads bundled `Secrets.plist` (gitignored) with Info.plist fallback; cached once at launch via `nonisolated(unsafe) static let`. Keys: `GEMINI_API_KEY`, `FATSECRET_PROXY_URL`, `FATSECRET_CLIENT_SECRET`. Safe to read directly from actors.

## Gotcha
- Everything UIKit-touching needs `#if canImport(UIKit)` guards or the macOS build breaks.
