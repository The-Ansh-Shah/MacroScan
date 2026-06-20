# MacroScan — Build Instructions (Iteration 6)

Reference: [ARCHITECTURE.md](ARCHITECTURE.md), [PROGRESS.md](PROGRESS.md), prior iterations V2–V5

This iteration improves data accuracy, durability, and a couple of small UX issues.

Changes:

1. **Split MeasurementsEditor** — separate sheets for logging today's measurement vs. editing profile; profile editor moves to Settings
2. **Macro rings show targets** — display "consumed / target" inside each ring, matching the WaterBar pattern
3. **Editable scan results** — let users correct OFF macro values before logging
4. **Verified Food persistence** — corrections persist; future scans of the same barcode use the user's trusted values
5. **JSON export / import** — full data backup that survives app uninstall

Read the entire document. Update `PROGRESS.md` as items complete. Commit each phase separately.

---

## Phase 36 — Split Measurements Editor

### Why
The current `MeasurementsEditor` handles two conceptually different actions in one form:
- Logging today's measurement (recurring action — every few days)
- Editing profile body fields (rare action — height, age, sex, activity level)

Conflating them makes the recurring action heavier than it needs to be. Split into two purpose-built views.

### New views

**`LogMeasurementSheet`** — today's data only:
- Weight (lb/kg)
- Waist (in/cm)
- Neck (in/cm)
- Hip (in/cm) — visible only if `UserProfile.biologicalSex == .female`
- Optional manual body fat %
- Optional notes
- Live Navy estimate display as circumferences are typed (existing behavior)
- Save creates a new `BodyMeasurement`

**`ProfileEditorSheet`** — stable profile fields only:
- Height (in/cm)
- Age (years)
- Biological sex (segmented: male / female / unspecified)
- Activity level (picker)
- Save updates `UserProfile` in place; does NOT create a `BodyMeasurement`

### MeView changes

- Keep the "Log measurement" button; present `LogMeasurementSheet`
- Remove the "Update measurements" button entirely
- Delete `showingMeasurementsEditor` state and its sheet presenter

### SettingsView changes

Add a new "Profile" section, near the top, above Apple Health:
- NavigationLink: **"Edit profile"** → presents `ProfileEditorSheet`
- Subtitle below the link summarizing current values: e.g., `5'10", 20, Male, Moderately Active`

### Cleanup

- Delete the original `MeasurementsEditor` once both replacements are wired
- Search for any lingering references (`grep -ri "MeasurementsEditor" Views/`) and clean up

### Verify
- MeView shows one measurement button, opens compact log sheet
- Settings has Edit profile link with current-values subtitle, opens profile sheet
- Editing profile in Settings does NOT create a new BodyMeasurement
- Logging measurement in MeView does NOT change profile fields
- Original MeasurementsEditor is gone

---

## Phase 37 — Macro Rings Show Targets

### Why
The macro rings on Today currently show consumed value but not the target — users can't see the goal at a glance unless they remember it. The `WaterBar` already shows "0 / 93 oz" inline; rings should match.

### Layout inside each ring

Stacked, centered:
- **Line 1**: consumed value, monospaced digits, bold, current `.mStatNumber` styling
- **Line 2**: `/ {target}` — smaller (~60% of line 1), `.mTextSecondary` color
- **Line 3**: unit label (cal, g), `.mCaption`, `.mTextTertiary`

When `consumed > target`:
- Line 1 switches to `.mOver` color (red)
- Lines 2 and 3 stay as-is

### Fitting

Ring real estate is tight, especially for 4-digit calorie targets:
- Tighten inner VStack spacing to `Spacing.xs` (4pt)
- Reduce line 1 font size as needed so 4-digit values (e.g., `1,768`) don't clip
- Test cases: calorie target ≥ 2000, protein target ≥ 150g

### Don't add anything else

Do NOT add a redundant horizontal summary strip below the rings or a separate target-display row. The rings should be the single source of truth for consumed-vs-target. If they don't fit, fix the rings — don't duplicate the data elsewhere.

### Verify
- Rings show `consumed` and `/ target` with proper hierarchy
- 0 consumed shows "0 / 1768" cleanly
- Going over target colors line 1 red
- No clipping on smallest iPhone width (iPhone SE 3rd gen, 375pt)

---

## Phase 38 — Editable Scan Results

### Why
Open Food Facts data is community-contributed and frequently wrong: decimal-point errors, per-100g vs. per-serving confusion, missing fields filled with zeros, regional variations, stale data. Users need to correct values before logging without leaving the scan flow.

### ScanResultSheet changes

Add a disclosure section labeled **"Nutrition (per {servingSizeGrams}g)"**, collapsed by default.

When expanded, exposes editable numeric fields for everything currently shown read-only:
- Calories
- Protein
- Carbs
- Fat
- Fiber
- Iron
- Vitamin D
- Vitamin B12

Each field uses the same numeric input styling as `ManualFoodForm`. No new components needed — reuse what's there.

At the bottom of the section:
- **"Reset to scanned values"** button — restores the originally-fetched OFF values

When any value differs from the originally-fetched value:
- Show a small `pencil.circle.fill` SF Symbol next to the section header indicating "Modified"
- Use `.mAccent` color for the icon

### Default workflow unchanged

Scan → adjust grams → log. Most logs don't expand the section. Keep the friction low for the common case.

### Persistence

When the user logs an entry with edited macro values, the corrections must be saved. This is the bridge to Phase 39 — implement the `userVerified` field there, not here.

For Phase 38 alone: the corrected values should at minimum be reflected in the resulting `LogEntry`'s computed macros (i.e., the saved `Food` object should reflect the corrections, not the original OFF data).

### Verify
- Scan a real product, expand nutrition section, edit calories from 250 to 500, log it
- Resulting LogEntry uses 500 cal, not 250
- Reset button restores original OFF values
- Modified indicator appears when any field is edited

---

## Phase 39 — Verified Food Persistence

### Why
Once a user has corrected a barcode's macros, they shouldn't have to do it again. Future scans of the same barcode should prefer the user's trusted values over re-fetching unreliable OFF data.

### Data model addition

Add to `Food`:

```swift
@Model
final class Food {
    // ... existing fields ...
    var userVerified: Bool        // true if user manually corrected the macros
    var lastVerifiedAt: Date?
}
```

Light migration: existing rows default `userVerified = false`, `lastVerifiedAt = nil`.

### Scan logic in FoodRepository

Replace the current scan-handling logic with this flow:

1. Barcode scanned → check local DB for existing `Food` with that barcode
2. If a local Food exists with `userVerified == true` → use it directly, skip the OFF call entirely. ScanResultSheet pre-fills with these values.
3. If a local Food exists but `userVerified == false` → still call OFF. If OFF returns different values, show user both: "Local: 250 cal • OFF: 245 cal — pick one." (Simple Alert with two buttons; default to local for stability.)
4. If no local Food exists → call OFF as today, save result locally on log
5. When user submits the scan log with any edited macro value, set `userVerified = true` and `lastVerifiedAt = Date()` on the saved Food

### UI signals

In `FoodRow` (the meal section list rows on DayView):
- When `food.userVerified == true`, show a small `checkmark.seal.fill` SF Symbol (system green) next to the food name
- Subtle — caption-size icon, doesn't dominate the row

In `ScanResultSheet` for a previously-verified food:
- Banner at top: "You've verified this food before. Macros shown are your saved values."
- Use `.mBgSecondary` background, `.mTextSecondary` foreground
- Dismissible? No — informational only, not blocking

### Verify
- Scan barcode A, edit calories from 250 to 500, log
- Scan barcode A again → sheet pre-fills with 500 cal, shows "verified" banner
- DayView rows for barcode A foods show green checkmark
- Scan barcode B without editing → logs normally, no checkmark, no banner

---

## Phase 40 — JSON Export and Import

### Why
The free Apple developer provisioning expires every 7 days. If you forget to re-sign, the app is uninstalled and SwiftData is lost. HealthKit sync covers some data (body measurements, nutrition writes) but not recipes, scan corrections, custom foods, water history, or LogEntry photos. Export gives durability.

Storage isn't a concern — even a year of heavy logging exports to ~1-2 MB JSON without photos.

### Export format

Single JSON file with a top-level schema:

```json
{
  "version": 1,
  "exportedAt": "2026-04-24T10:30:00Z",
  "appVersion": "1.0.0",
  "userProfile": { ... },
  "foods": [ ... ],
  "logEntries": [ ... ],
  "bodyMeasurements": [ ... ],
  "waterEntries": [ ... ],
  "recipes": [ ... ],
  "weightGoals": [ ... ]
}
```

Each entity exports all stored fields. Photos in `LogEntry.photoData` are base64-encoded inline (acceptable size for personal use).

### Service

New `DataExportService`:

```swift
actor DataExportService {
    enum ExportError: Error {
        case encodingFailed(Error)
        case fileWriteFailed(Error)
    }
    
    enum ImportError: Error {
        case fileReadFailed(Error)
        case invalidFormat
        case versionUnsupported(Int)
        case decodingFailed(Error)
    }
    
    func exportAll() async throws -> URL  // returns file URL in temp directory
    func importFrom(_ url: URL) async throws -> ImportResult
}

struct ImportResult {
    let foodsAdded: Int
    let foodsSkipped: Int      // already existed
    let logEntriesAdded: Int
    let logEntriesSkipped: Int
    let measurementsAdded: Int
    let measurementsSkipped: Int
    // ... per entity type
}
```

Implementation notes:
- Use `JSONEncoder` with `.iso8601` date strategy and `.prettyPrinted` for readability
- All `@Model` classes need to either conform to `Codable` already or have `Encodable`/`Decodable` snapshot DTOs (cleaner — avoids polluting SwiftData models with codable conformance)
- Recommend: define `FoodDTO`, `LogEntryDTO`, etc., as plain structs that mirror the `@Model` fields. Convert in both directions in the service. Keeps export schema decoupled from internal model changes.
- Import deduplication: match on UUIDs. If an entity with the same ID exists, skip (don't overwrite). If you want overwrite semantics later, that's a v2 decision.

### Settings UI

Add a "Data" section to SettingsView:

- **Export data** button → calls `exportAll()`, presents `ShareSheet` with the resulting file URL (user picks where to save: iCloud Drive, Files, AirDrop to Mac, etc.)
- **Import from file** button → presents `UIDocumentPicker` for `.json` files; on selection, calls `importFrom(_:)` and shows result alert: "Added 12 foods, 87 log entries, 3 measurements. Skipped 4 entries that already existed."

Show a brief explainer below the buttons:
> "Export creates a complete backup of your foods, logs, recipes, and measurements. Import merges data from a previous export — existing entries are kept, new ones added."

### Photo handling

`LogEntry.photoData` blobs make export files significantly larger. Two options:

**Option A (chosen for v1):** include photos inline as base64. Simple, complete. File might be 50 MB+ for a year of heavy AI-photo use, but still trivially manageable.

**Option B (later):** export photos as separate files in a folder, ZIP everything together. More work; defer unless export files become unwieldy.

Use Option A for v1. Add a future TODO comment.

### Edge cases

- Empty database → still produces a valid JSON file with empty arrays
- Import a file from a future schema version → throw `versionUnsupported`, show clear error message
- Import a malformed file → throw `invalidFormat`, surface parsing errors clearly
- Import while app has data → merge, never wipe

### Verify
- Export from a populated database → file contains all entities, opens cleanly in any text editor
- Wipe local data (delete app + reinstall), import the exported file → all entities restored, computed properties (macros from log entries, etc.) work correctly
- Import on top of existing data → no duplicates, skipped count matches expectation

---

## Progress updates

Append to `PROGRESS.md`:

```markdown
# Iteration 6

## Phase 36 — Split Measurements Editor
- [ ] LogMeasurementSheet (today's data only)
- [ ] ProfileEditorSheet (stable profile fields only)
- [ ] MeView wired to LogMeasurementSheet; "Update measurements" removed
- [ ] SettingsView Profile section with Edit profile link + values subtitle
- [ ] Original MeasurementsEditor deleted; references cleaned
- [ ] **Verify:** distinct flows, no cross-contamination of data

## Phase 37 — Macro Rings Show Targets
- [ ] MacroRingsView displays consumed / target / unit stack
- [ ] Over-target switches consumed line to .mOver color
- [ ] Spacing tightened, font sized to fit 4-digit values
- [ ] No redundant summary strip added elsewhere
- [ ] **Verify:** clean display at all values; no clipping on smallest iPhone

## Phase 38 — Editable Scan Results
- [ ] Nutrition disclosure section in ScanResultSheet (collapsed default)
- [ ] All macro + micro fields editable
- [ ] "Reset to scanned values" button
- [ ] Modified indicator (pencil.circle.fill, .mAccent) when fields differ
- [ ] Edited values reflected in saved Food / LogEntry macros
- [ ] **Verify:** scan, edit calories, log → LogEntry uses corrected value

## Phase 39 — Verified Food Persistence
- [ ] Food.userVerified + lastVerifiedAt fields with migration
- [ ] Scan logic prefers local userVerified Food over OFF call
- [ ] Conflict resolution UI when local unverified differs from OFF
- [ ] Edited scan logs set userVerified = true, lastVerifiedAt = Date()
- [ ] FoodRow shows checkmark.seal.fill (green) for verified foods
- [ ] ScanResultSheet shows "verified" banner for previously-edited barcodes
- [ ] **Verify:** scan A → edit → log; rescan A → pre-filled, banner shown, checkmark visible

## Phase 40 — JSON Export and Import
- [ ] DataExportService actor with exportAll + importFrom
- [ ] DTO structs for all @Model types
- [ ] JSON schema with version, exportedAt, all entity arrays
- [ ] Photos base64-encoded inline (Option A; Option B deferred)
- [ ] Settings → Data section with Export + Import buttons
- [ ] Export uses ShareSheet; Import uses UIDocumentPicker
- [ ] ImportResult with per-entity added/skipped counts; alert on completion
- [ ] UUID-based dedup on import (skip existing, no overwrite)
- [ ] Version mismatch + malformed file errors handled clearly
- [ ] **Verify:** export → wipe → import → all data restored, no duplicates

## Phase 41 — Migrate Barcode Scanning to FatSecret
- [ ] `FatSecretAPI.barcodeLookup(barcode:)` + `foodDetail(id:)` methods added
- [ ] FoodRepository scan path calls FatSecret, not OFF
- [ ] Barcode-not-found → manual entry prompt (no OFF fallback)
- [ ] OFF call sites audited; `OpenFoodFactsAPI.swift` deleted if no callers remain
- [ ] `FoodSource.openFoodFacts` case removed; DB migration block in RootView.onAppear
- [ ] ScanResultSheet source label/icon updated to FatSecret
- [ ] Rate limit guard covers barcode calls (shared 4500/day threshold)
- [ ] **Verify:** real barcode → FatSecret data; unknown barcode → manual prompt; OFF file gone
```

---

## Build Order

1. **Phase 41** - update from open source api usage
2. **Phase 36** — measurement split. Small, isolated, ships immediately.
3. **Phase 37** — macro rings. Small visual change, ships immediately.
4. **Phase 38** — editable scan results. Foundation for Phase 39.
5. **Phase 39** — verified persistence. Builds directly on Phase 38.
6. **Phase 40** — JSON export. Largest phase but isolated; touches Settings + new service.

Estimated total: 5-7 hours.

## Constraints

- Follow `ARCHITECTURE.md` §15 conventions
- No new external Swift packages
- No new AI integrations
- Every new view uses DesignSystem tokens
- Commit after each phase passes verify
- Phase 38 + 39 commit separately even though they're tightly related — easier to bisect if regressions appear
- Phase 40 export schema starts at `version: 1` — increment on any breaking change to entity shape
