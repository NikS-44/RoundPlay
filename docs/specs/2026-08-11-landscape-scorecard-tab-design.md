# Landscape Scorecard Tab — Design

**Date:** 2026-08-11
**Status:** Approved design, pending implementation plan

---

## 1. Premise

The full grid scorecard is only reachable once a round is finished. During a round you can see
the hole you are on and the standings, but not the card. Golfers check the card mid-round
constantly: to see where a match stands, to check what someone made on a hole three back, to
settle an argument before it becomes one.

This adds the grid to the round's tab bar, in landscape, in both the in-progress and the
finished state.

### Non-goals

- Editing scores from the grid. It stays read-only; the Hole tab is where scores are entered.
- Any change to the scoring engine, settlements, or the share image.
- Any change to the app's portrait-only policy outside this one screen.

---

## 2. What already exists

Most of this is built. The work is routing, a rename, and one new capability.

| Component | Where | Status |
|---|---|---|
| `ScorecardGrid` | `PaperScorecardView.swift` | Built. Sticky label column, one horizontally scrolling region for all rows. |
| `FullScreenScorecardView` | `PaperScorecardView.swift` | Built. Landscape wrapper, requests rotation on appear, restores portrait on disappear. |
| `OrientationLock` | `Core/OrientationLock.swift` | Built. Drives `RoundPlayAppDelegate`'s supported-orientation mask. |
| `PaperScorecardView` | `PaperScorecardView.swift` | Built, portrait. **To be removed** (see §4). |
| `ShareableRoundCard` | `PaperScorecardView.swift` | Built. Renders `ScorecardGrid(forSharing: true)` to a `UIImage`. Must keep working. |

---

## 3. Tab structure

The round's own tab bar changes in both states. Note that `.toolbar(.hidden, for: .tabBar)` in
`RoundTabsView` hides the *app's* Rounds/Games/Roster bar while a round is open; the round's tab
bar is separate and stays visible.

**In progress:** `Hole` · `Scorecard` · `Standings`

**Finished:** `Summary` · `Scorecard` · `Standings`

`Scorecard` means the landscape grid in both states. This is the point of the change: today the
same word means the hole-entry screen mid-round and the grid once finished, so it already means
two things depending on state.

| Tab | Icon | Content |
|---|---|---|
| Hole | `flag.fill` | `HoleScreenView`, unchanged apart from the label and icon |
| Scorecard | `square.grid.3x3` | The landscape grid, in both states |
| Standings | `chart.bar` | `RoundDashboardView`, unchanged |
| Summary | `checkmark.seal` | `RoundSummaryView`, finished rounds only, unchanged |

`navigationTitleText` gains a `.hole` case. The `showsDarkNavBar` rule follows the Hole tab
rather than `.scorecard`, since the near-black `HoleHeader` is what the light nav bar exists for.

---

## 4. Removals

Approved explicitly: unify on one scorecard presentation and delete the other.

- **`PaperScorecardView`** (the portrait grid) is deleted. Its only call site is the finished
  round's Scorecard tab, which now shows the landscape grid.
- **The toolbar expand button** on the finished Scorecard tab is deleted, along with the
  `isFullScreen` state and the `fullScreenCover` that presented it.
- **`FullScreenScorecardView`'s close button** is deleted. The tab bar is the way out, so a
  close button would be a second, redundant exit. The view is otherwise kept and becomes the
  tab's content.

`RoundSummaryView`'s `onShowScorecard` callback changes meaning: instead of presenting the
cover, it selects the Scorecard tab. Its row keeps its label and subtitle.

**Consequence to accept:** there is no longer any way to read a finished card in portrait. This
was the explicit decision.

---

## 5. Current-hole focus

`ScorecardGrid` gains `var focusHole: Int? = nil`.

- When non-nil, the scrolling region is wrapped in a `ScrollViewReader` and scrolls that hole's
  column into view on appear.
- That column's header cell is tinted with `RoundPlayColors.holeActive`.
- When nil, behaviour is byte-for-byte today's. The `forSharing: true` render path passes nil,
  so the share image is unaffected.

**Current hole** = the first hole in `round.holeSegment.holeRange` for which
`state.isComplete(hole:)` is false; if every hole is complete, the last hole in the range. This
is the same rule `InProgressRoundCard` already uses to compute "thru N", so the card and the grid
cannot disagree.

A finished round therefore focuses its last hole, which is the correct place to land when
reviewing a card you just completed.

---

## 6. Orientation

`FullScreenScorecardView` currently drives the lock from its own `onAppear`/`onDisappear`. As tab
content this is a risk: SwiftUI does not guarantee `onDisappear` fires when a tab is deselected,
and a missed call would strand the app in landscape.

**Decision:** drive the lock from `RoundTabsView` instead, with
`.onChange(of: selection)` requesting landscape when the selection becomes `.scorecard` and
portrait otherwise, plus `requestPortrait()` when the round view is dismissed. Selection is state
we own and observe deterministically. The grid view no longer touches `OrientationLock`.

**To verify first, before building on it:** that the round's tab bar renders usably in landscape
on a real device size. If it does not, the fallback is to keep the grid as a `fullScreenCover`
with its close button and trigger it from tab selection, reverting the selection immediately. The
whole design depends on the tab bar being the exit, so this is checked first.

The nav bar is hidden on the Scorecard tab in landscape. Vertical space is the scarce dimension
there, and the tab already names itself.

---

## 7. Testing

**Unit (engine-adjacent, no UI):** the current-hole rule, extracted so it can be tested directly.

| Case | Expected |
|---|---|
| Fresh 18-hole round, nothing scored | 1 |
| 18-hole round, holes 1–6 complete | 7 |
| 18-hole round, all complete | 18 |
| Back-nine round, nothing scored | 10 |
| Back-nine round, 10–12 complete | 13 |
| Hole 3 partially scored (one of four players) | 3, not 4 |

**Regression:** the 88 existing engine tests must stay green, and the share image must still
render at the correct intrinsic width for both 9- and 18-hole rounds. `ScorecardGrid`'s
`intrinsicWidth` is load-bearing for the share card and is not changed by this work.

**Manual, in the simulator:** rotation on entering and leaving the tab; rotation restored when
exiting the round entirely from the Scorecard tab; the tab bar usable in landscape; focus and
tint land on the right column mid-round; the grid renders correctly with unscored holes blank.

---

## 8. Files touched

| File | Change |
|---|---|
| `RoundsHomeView.swift` (`RoundTabsView`) | Tab labels and icons, `.hole` case, orientation `onChange`, remove `isFullScreen` + `fullScreenCover` + expand toolbar button |
| `PaperScorecardView.swift` | Delete `PaperScorecardView`; `focusHole` on `ScorecardGrid`; drop close button and orientation calls from `FullScreenScorecardView` |
| `RoundSummaryView.swift` | `onShowScorecard` selects the tab rather than presenting a cover |

`RoundTabsView` currently lives inside `RoundsHomeView.swift` at line 463, in a file of 686 lines
that also holds the rounds list, the in-progress card, the earlier-round row and the empty state.
Moving `RoundTabsView` to its own file is a reasonable part of this change, since this work
touches its tab structure, toolbar and presentation modifiers, and it would leave both files
covering one screen each.
