# RoundPlay Phase 0 — Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the RoundPlay repository, a testable Swift package for the scoring engine, and an iOS app target with the ported design system and a RoundPlay color scheme.

**Architecture:** Two units. `Packages/RoundPlayEngine` is a pure Swift package with no UI dependency — it holds all scoring logic and is tested with `swift test`. `RoundPlay/` is the iOS app target, generated from `project.yml` via XcodeGen so the project file stays diffable. The app depends on the package; the package knows nothing about the app.

**Tech Stack:** Swift 6.2, SwiftUI + Observation, SwiftData (local only), XcodeGen, swift-testing.

## Execution Mode

Run this plan's tasks continuously, start to finish, without pausing for step-by-step
approval or asking "should I proceed?" between tasks. Run each verification command as
specified and move on when it passes. **Only stop and ask the user when a decision is
genuinely controversial or ambiguous** — a product/scope/rules judgment call this plan
doesn't already resolve, not an implementation detail. When you do have a reasonable
recommendation, state it briefly and keep going rather than blocking on confirmation.
This applies to every plan in this project, in this session and any future one.

## Global Constraints

- Swift tools version **6.2**; iOS deployment target **18.0**.
- **Do not run `xcodebuild` during implementation.** Verification for the package is `swift test`. The app target is edits-only; the user builds in Xcode.
- The engine package must **never** import SwiftUI, UIKit, SwiftData, or Foundation networking. Its only dependency is `Foundation`.
- No CloudKit anywhere in this project.
- Source of truth for design decisions: `docs/specs/2026-08-08-roundplay-design.md`.
- Ported UpKeepr files must have `UpKeepr` renamed to `RoundPlay` in type names, and the header comment must be trimmed of UpKeepr-domain references.
- Every file gets a doc comment on its primary type. Match UpKeepr's comment density — explain *why*, not *what*.

---

### Task 1: Repository and engine package skeleton

**Files:**
- Create: `/Users/nik/workplace/RoundPlay/.gitignore`
- Create: `/Users/nik/workplace/RoundPlay/README.md`
- Create: `/Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine/Package.swift`
- Create: `/Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine/Sources/RoundPlayEngine/RoundPlayEngine.swift`
- Test: `/Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine/Tests/RoundPlayEngineTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: the `RoundPlayEngine` module, importable as `import RoundPlayEngine`. `RoundPlayEngineVersion.current: String`.

- [ ] **Step 1: Initialize the repository**

```bash
cd /Users/nik/workplace/RoundPlay
git init
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
.DS_Store
*.xcodeproj
!project.yml
xcuserdata/
*.xcworkspace/xcuserdata/
.build/
.swiftpm/
DerivedData/
```

Note: `*.xcodeproj` is ignored deliberately — it is generated from `project.yml` by XcodeGen and must never be committed.

- [ ] **Step 3: Write `README.md`**

```markdown
# RoundPlay

Golf betting games, scored on the course.

## Layout

- `Packages/RoundPlayEngine/` — pure Swift scoring engine. No UI, no I/O. `swift test` to verify.
- `RoundPlay/` — iOS app target. Generated project; run `xcodegen generate` after editing `project.yml`.
- `docs/specs/` — design documents.
- `docs/plans/` — implementation plans.

## Building

```bash
brew install xcodegen     # once
xcodegen generate         # regenerate RoundPlay.xcodeproj
open RoundPlay.xcodeproj
```

## Testing the engine

```bash
cd Packages/RoundPlayEngine && swift test
```
```

- [ ] **Step 4: Write `Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoundPlayEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RoundPlayEngine", targets: ["RoundPlayEngine"])
    ],
    targets: [
        .target(name: "RoundPlayEngine"),
        .testTarget(
            name: "RoundPlayEngineTests",
            dependencies: ["RoundPlayEngine"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```

`resources: [.copy("Fixtures")]` is declared now even though the directory is empty, so Phase 1a can drop JSON fixtures in without touching `Package.swift`. Create the directory with a placeholder so SwiftPM does not warn:

```bash
mkdir -p Packages/RoundPlayEngine/Tests/RoundPlayEngineTests/Fixtures
touch Packages/RoundPlayEngine/Tests/RoundPlayEngineTests/Fixtures/.gitkeep
```

- [ ] **Step 5: Write the failing smoke test**

Create `Packages/RoundPlayEngine/Tests/RoundPlayEngineTests/SmokeTests.swift`:

```swift
import Testing
@testable import RoundPlayEngine

@Test("Engine module is importable and reports its version")
func engineVersionIsPresent() {
    #expect(RoundPlayEngineVersion.current == "0.1.0")
}
```

- [ ] **Step 6: Run the test to verify it fails**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: FAIL — `cannot find 'RoundPlayEngineVersion' in scope`.

- [ ] **Step 7: Write the minimal implementation**

Create `Packages/RoundPlayEngine/Sources/RoundPlayEngine/RoundPlayEngine.swift`:

```swift
import Foundation

/// Marker for the engine module's rule-set version.
///
/// Bump this whenever a scoring rule changes in a way that would alter the money a past
/// round settled to. The web port (Phase 4) checks this against its own constant so the two
/// implementations cannot silently drift apart.
public enum RoundPlayEngineVersion {
    public static let current = "0.1.0"
}
```

- [ ] **Step 8: Run the test to verify it passes**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: PASS — 1 test passed.

- [ ] **Step 9: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add .gitignore README.md Packages docs
git commit -m "chore: initialize RoundPlay repo and engine package"
```

---

### Task 2: iOS app target via XcodeGen

**Files:**
- Create: `/Users/nik/workplace/RoundPlay/project.yml`
- Create: `/Users/nik/workplace/RoundPlay/RoundPlay/RoundPlayApp.swift`
- Create: `/Users/nik/workplace/RoundPlay/RoundPlay/RoundPlayAppDelegate.swift`
- Create: `/Users/nik/workplace/RoundPlay/RoundPlay/ContentView.swift`
- Create: `/Users/nik/workplace/RoundPlay/RoundPlay/Models/AppearancePreference.swift`
- Create: `/Users/nik/workplace/RoundPlay/RoundPlay/Assets.xcassets/` (AccentColor, AppIcon placeholders)

**Interfaces:**
- Consumes: `RoundPlayEngine` from Task 1.
- Produces: `RoundPlayApp` (`@main`), `ContentView` (three-tab shell), `AppearancePreference` enum with `.system/.light/.dark` and `appStorageKey`.

> **Porting note:** UpKeepr's `ContentView.swift` (443 lines) and `UpKeeprAppDelegate.swift` import CloudKit and coordinate household sync, habit deep links, and six services. **Do not copy them.** The only genuinely reusable parts are reproduced verbatim below: the `UITableView.appearance()` separator configuration (which `RoundPlayList` depends on for full-width separators) and the first-launch splash gate.

- [ ] **Step 1: Install XcodeGen**

```bash
brew install xcodegen
```

- [ ] **Step 2: Write `project.yml`**

```yaml
name: RoundPlay
options:
  bundleIdPrefix: app.roundplay
  deploymentTarget:
    iOS: "18.0"
  createIntermediateGroups: true

packages:
  RoundPlayEngine:
    path: Packages/RoundPlayEngine

targets:
  RoundPlay:
    type: application
    platform: iOS
    sources:
      - path: RoundPlay
    dependencies:
      - package: RoundPlayEngine
        product: RoundPlayEngine
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.roundplay.RoundPlay
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "6.2"
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait
        ENABLE_USER_SCRIPT_SANDBOXING: YES
```

Portrait-only is deliberate: the hole screen is a one-handed, thumb-reachable layout and landscape adds work with no user benefit.

- [ ] **Step 3: Write `AppearancePreference.swift`**

Create `RoundPlay/Models/AppearancePreference.swift`:

```swift
import SwiftUI

/// User-selected light/dark override, persisted in `UserDefaults` via `@AppStorage`.
///
/// Ported from UpKeepr unchanged — the pattern is domain-neutral.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let appStorageKey = "appearancePreference"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
```

- [ ] **Step 4: Write `RoundPlayAppDelegate.swift`**

Create `RoundPlay/RoundPlayAppDelegate.swift`. This is the distilled 20 lines worth keeping from UpKeepr's delegate — everything CloudKit, household, and habit-related is dropped.

```swift
import UIKit
import UserNotifications

/// UIKit bridge.
///
/// Its one job today is the table-view appearance configuration below. `RoundPlayList`
/// relies on it: without `separatorInset = .zero` and `separatorInsetReference = .fromCellEdges`,
/// SwiftUI insets list separators to the title column and rows with a leading element render
/// with a ragged gap.
final class RoundPlayAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        let table = UITableView.appearance()
        table.separatorInset = .zero
        table.layoutMargins = .zero
        table.separatorInsetReference = .fromCellEdges
        table.keyboardDismissMode = .interactive
        UITableViewCell.appearance().layoutMargins = .zero

        return true
    }
}
```

- [ ] **Step 5: Write `RoundPlayApp.swift`**

Create `RoundPlay/RoundPlayApp.swift`. No `ModelContainer` yet — SwiftData arrives in Phase 1b.

```swift
import SwiftUI

@main
struct RoundPlayApp: App {
    @UIApplicationDelegateAdaptor(RoundPlayAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- [ ] **Step 6: Write `ContentView.swift`**

Create `RoundPlay/ContentView.swift`. Three tabs matching the spec's flows; each is a placeholder until Phase 1b.

```swift
import SwiftUI

/// Root tab shell.
///
/// Tabs map to the three things a user does: start or resume a round, browse the game
/// library, and manage their roster of playing companions.
struct ContentView: View {
    @AppStorage(AppearancePreference.appStorageKey)
    private var appearancePreferenceRaw = AppearancePreference.system.rawValue

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearancePreferenceRaw) ?? .system
    }

    var body: some View {
        TabView {
            Tab("Rounds", systemImage: "flag.circle") {
                NavigationStack { Text("Rounds").navigationTitle("Rounds") }
            }
            Tab("Games", systemImage: "list.bullet.rectangle") {
                NavigationStack { Text("Game Library").navigationTitle("Games") }
            }
            Tab("Players", systemImage: "person.2") {
                NavigationStack { Text("Players").navigationTitle("Players") }
            }
        }
        .preferredColorScheme(appearancePreference.colorScheme)
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 7: Create the asset catalog**

```bash
mkdir -p RoundPlay/Assets.xcassets/AccentColor.colorset
mkdir -p RoundPlay/Assets.xcassets/AppIcon.appiconset
```

`RoundPlay/Assets.xcassets/Contents.json`:

```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

`RoundPlay/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [ { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`RoundPlay/Assets.xcassets/AccentColor.colorset/Contents.json` — fairway green, the app accent. Light and dark variants so the accent stays legible on both:

```json
{
  "colors" : [
    {
      "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0.106", "green" : "0.451", "blue" : "0.290", "alpha" : "1.000" }
      }
    },
    {
      "idiom" : "universal",
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0.310", "green" : "0.741", "blue" : "0.529", "alpha" : "1.000" }
      }
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 8: Generate the project**

```bash
cd /Users/nik/workplace/RoundPlay && xcodegen generate
```

Expected: `Created project at /Users/nik/workplace/RoundPlay/RoundPlay.xcodeproj`.

- [ ] **Step 9: Verify the engine package still resolves**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: PASS. (Per Global Constraints, do not run `xcodebuild` — the user builds the app target in Xcode.)

- [ ] **Step 10: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add project.yml RoundPlay
git commit -m "feat: add iOS app target with tab shell"
```

---

### Task 3: Design system port and RoundPlay color tokens

**Files:**
- Create: `RoundPlay/DesignSystem/RoundPlayColors.swift`
- Create: `RoundPlay/DesignSystem/RoundPlayList.swift`
- Create: `RoundPlay/DesignSystem/HubComponents.swift`
- Create: `RoundPlay/DesignSystem/AccordionSection.swift`
- Create: `RoundPlay/DesignSystem/CompletionCheckbox.swift`
- Create: `RoundPlay/DesignSystem/GlassSheet.swift`
- Create: `RoundPlay/DesignSystem/RenameSheet.swift`
- Create: `RoundPlay/DesignSystem/AccentOutlineButtonStyle.swift`
- Create: `RoundPlay/DesignSystem/RedOutlineButtonStyle.swift`
- Create: `RoundPlay/DesignSystem/ListRowComponents.swift`
- Create: `RoundPlay/DesignSystem/CelebrationOverlay.swift`
- Create: `RoundPlay/DesignSystem/FireworksScene.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `RoundPlayColors` (enum of static `Color`), `RoundPlayList.plain(content:)`, `RoundPlayRowButtonStyle`, `ChipButton`, `SegmentedPill<Value>`, `HubRow`, `HubSectionLabel`, `FlowLayout`, `AccordionSection`, `CompletionCheckbox`, `GlassSheet`, `RenameSheet`, `CelebrationOverlay`, and `View.roundPlayListRowSeparatorFullWidth()`.

**Source for ports:** `/Users/nik/workplace/UpKeepr/UpKeepr/DesignSystem/`.

**Do NOT port these** — they are UpKeepr-domain-specific and have no RoundPlay equivalent: `UpkeepaMascot.swift`, `HabitWeekStrip.swift`, `HabitCelebrationRow.swift`, `WeekPlanDateRange.swift`, `WeekScrollerBar.swift`, `Streaks/`, `UpKeeprLibrary.swift`, `LaunchSplashView.swift`, `CelebrationMessages.swift`.

- [ ] **Step 1: Write `RoundPlayColors.swift`**

This is a **rewrite, not a port**. UpKeepr's token set is ~70% domain-specific (breathing phases, streak tiers, meal planner, workout coaching). Only the generic fills and semantic tokens carry over; the rest are new and golf-specific.

Create `RoundPlay/DesignSystem/RoundPlayColors.swift`:

```swift
import SwiftUI
import UIKit

/// Semantic colors for RoundPlay. Prefer these over raw `.red`, `.green`, etc. in feature code.
///
/// Tokens may share values, but the names let us retune one meaning without touching the others.
/// Every token must be legible in **both** light and dark — the app is used outdoors in direct
/// sun, where low-contrast greys disappear entirely.
enum RoundPlayColors {

    // MARK: - Brand

    /// App accent — fairway green, from `Assets.xcassets/AccentColor`.
    static let accent = Color.accentColor

    // MARK: - Scoring

    /// Score at or under par.
    static let scoreUnderPar = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.82, blue: 0.55, alpha: 1)
            : UIColor(red: 0.09, green: 0.52, blue: 0.28, alpha: 1)
    })
    /// Score at par — deliberately neutral so birdies and blowups are what catch the eye.
    static let scoreAtPar = Color.primary
    /// Score over par.
    static let scoreOverPar = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.52, blue: 0.48, alpha: 1)
            : UIColor(red: 0.75, green: 0.20, blue: 0.16, alpha: 1)
    })
    /// The hole currently being scored.
    static let holeActive = Color.accentColor
    /// A hole with no score entered yet.
    static let holePending = Color(uiColor: .tertiaryLabel)

    // MARK: - Money

    /// Player is up money.
    static let moneyPositive = scoreUnderPar
    /// Player is down money.
    static let moneyNegative = scoreOverPar
    /// Player is even.
    static let moneyEven = Color.secondary
    /// Payments not yet available — the greyed-out Settle Up affordance.
    static let moneyDisabled = Color(uiColor: .quaternaryLabel)

    // MARK: - Connection state

    /// Socket open, outbox empty.
    static let connectionLive = scoreUnderPar
    /// Reachable, outbox draining.
    static let connectionSyncing = Color.orange
    /// Unreachable — scores are queued locally.
    static let connectionOffline = scoreOverPar

    // MARK: - Destructive

    static let destructive = Color.red

    // MARK: - Fills

    /// Primary "chip/card on a list background" fill; respects light/dark.
    static let fillSecondary = Color(uiColor: .secondarySystemFill)
    /// Lighter fill for layered chips on a card that already uses `fillSecondary`.
    static let fillTertiary = Color(uiColor: .tertiarySystemFill)
    /// Grouped-list / card background.
    static let backgroundSecondaryGrouped = Color(uiColor: .secondarySystemBackground)
    /// Page background.
    static let backgroundSystem = Color(uiColor: .systemBackground)
}
```

- [ ] **Step 2: Port `RoundPlayList.swift`**

Copy `/Users/nik/workplace/UpKeepr/UpKeepr/DesignSystem/UpKeeprList.swift` to `RoundPlay/DesignSystem/RoundPlayList.swift` and apply exactly these renames:

| From | To |
|---|---|
| `enum UpKeeprList` | `enum RoundPlayList` |
| `func upkeeprListRowSeparatorFullWidth()` | `func roundPlayListRowSeparatorFullWidth()` |
| `struct UpKeeprRowButtonStyle` | `struct RoundPlayRowButtonStyle` |
| `UpKeeprColors.fillSecondary` | `RoundPlayColors.fillSecondary` |
| `UpKeeprAppDelegate` (in comments) | `RoundPlayAppDelegate` |

Also update the doc comment: the original warns about ambiguity with "the SwiftData `List` model type in this target." RoundPlay has no `List` model, but keep the wrapper anyway — it centralizes `.listStyle(.plain)` and `.scrollDismissesKeyboard(.interactively)`. Reword the comment to say so rather than leaving a false claim in the file.

Drop `ListItemRowSeparatorStyle` — it is keyed to UpKeepr's todo/grocery row distinction, which has no analogue here.

- [ ] **Step 3: Port the remaining design system files**

For each file below, copy from `/Users/nik/workplace/UpKeepr/UpKeepr/DesignSystem/` and rename `UpKeeprColors` → `RoundPlayColors`, `UpKeepr` → `RoundPlay` in any type or function name, and delete any token reference that does not exist in the new `RoundPlayColors` (substituting the nearest surviving token):

| File | Notes |
|---|---|
| `HubComponents.swift` | Keep `HubSectionLabel`, `HubRow`, `ChipButton`, `SegmentedPill`, `MutedProminentButtonStyle`, `ThemedCardFill`, `ThemedCardBackground`, `FlowLayout`. **Delete `UpKeeprTemplateRowLabel`** — it is bound to UpKeepr's checklist templates. |
| `AccordionSection.swift` | Port as-is. |
| `CompletionCheckbox.swift` | Port as-is. |
| `GlassSheet.swift` | Port as-is. |
| `RenameSheet.swift` | Port as-is. |
| `AccentOutlineButtonStyle.swift` | Port as-is. |
| `RedOutlineButtonStyle.swift` | Uses `.red`; point at `RoundPlayColors.destructive`. |
| `ListRowComponents.swift` | Port as-is (11 lines). |
| `CelebrationOverlay.swift` | Port. Used at round completion. Strip any `CelebrationMessages` reference — that file is not ported; pass the message in as a `String` parameter instead. |
| `FireworksScene.swift` | Port as-is. Dependency of `CelebrationOverlay`. |

- [ ] **Step 4: Wire a design system gallery into the app shell**

Replace the `Games` tab placeholder in `RoundPlay/ContentView.swift` temporarily so the ported components are visually verifiable. Change the `Tab("Games", ...)` block to:

```swift
            Tab("Games", systemImage: "list.bullet.rectangle") {
                NavigationStack { DesignSystemGallery() }
            }
```

Create `RoundPlay/DesignSystem/DesignSystemGallery.swift`:

```swift
import SwiftUI

/// Scratch screen for eyeballing ported design system components in light and dark.
///
/// Temporary — Phase 1b replaces the Games tab with the real game library. Delete this file then.
struct DesignSystemGallery: View {
    @State private var selection = 0

    var body: some View {
        RoundPlayList.plain {
            HubSectionLabel(title: "Buttons")
            Button("Accent Outline") {}.buttonStyle(AccentOutlineButtonStyle())
            Button("Destructive") {}.buttonStyle(RedOutlineButtonStyle())

            HubSectionLabel(title: "Chips")
            ChipButton(title: "Skins", isSelected: true) {}
            ChipButton(title: "Nassau", isSelected: false) {}

            HubSectionLabel(title: "Scoring colors")
            Text("Birdie").foregroundStyle(RoundPlayColors.scoreUnderPar)
            Text("Par").foregroundStyle(RoundPlayColors.scoreAtPar)
            Text("Bogey").foregroundStyle(RoundPlayColors.scoreOverPar)

            HubSectionLabel(title: "Connection")
            Text("Live").foregroundStyle(RoundPlayColors.connectionLive)
            Text("Syncing").foregroundStyle(RoundPlayColors.connectionSyncing)
            Text("Offline").foregroundStyle(RoundPlayColors.connectionOffline)
        }
        .navigationTitle("Design System")
    }
}

#Preview("Light") { NavigationStack { DesignSystemGallery() } }
#Preview("Dark") {
    NavigationStack { DesignSystemGallery() }.preferredColorScheme(.dark)
}
```

**Required signature — Phase 1b depends on it.** After porting, `ChipButton` must expose exactly:

```swift
ChipButton(title: String, isSelected: Bool, action: @escaping () -> Void)
```

and `FlowLayout` must accept `FlowLayout(spacing:)`. If UpKeepr's versions differ, adapt them *here* rather than at the call sites — `WolfPromptView` and `HoleEventsPromptView` in Phase 1b are written against these signatures.

- [ ] **Step 5: Regenerate the project**

```bash
cd /Users/nik/workplace/RoundPlay && xcodegen generate
```

Expected: project regenerates with the new `DesignSystem` group.

- [ ] **Step 6: Verify design system files carry no UpKeepr references**

```bash
cd /Users/nik/workplace/RoundPlay && grep -rn "UpKeepr\|Upkeepa\|upkeepr" RoundPlay/ || echo "CLEAN"
```

Expected: `CLEAN`. Any hit is an incomplete rename — fix it before committing.

- [ ] **Step 7: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add RoundPlay/DesignSystem RoundPlay/ContentView.swift
git commit -m "feat: port design system and add RoundPlay color tokens"
```

---

## Phase 0 exit criteria

- [ ] `cd Packages/RoundPlayEngine && swift test` passes.
- [ ] `xcodegen generate` produces `RoundPlay.xcodeproj` without error.
- [ ] `grep -rn "UpKeepr" RoundPlay/` returns nothing.
- [ ] **User verification (Xcode, not automated):** app launches to a three-tab shell; the Design System gallery renders correctly in both light and dark.

Phase 1a (`2026-08-08-roundplay-phase-1a-engine.md`) is next and depends only on Task 1.
