# Solo Mode — Design

**Date:** 2026-09-05
**Status:** Draft, pending review

---

## 1. Premise

RoundPlay is built for a group: four seats, side bets, and a scorekeeper entering everyone's
numbers. A lot of golf isn't that. A solo round has one score per hole and nothing to settle, and
every part of the UI that exists to keep four players and their money straight becomes friction.

**Solo mode is the same round with one seat, and a scoring screen shaped for it.** No games, no
money, no Standings tab, no player names — the whole screen given over to entering one number as
fast and as certainly as possible.

It is not a separate kind of round. A solo round is an ordinary `RoundRecord` with one
`SeatRecord`, stored and synced like any other, and it appears on the Rounds home, the scorecard,
and in history alongside every group round.

Today solo is unreachable: `NewRoundModel.playerCount` clamps to `max(2, min(8, newValue))`, so
the player-count step cannot go below two even though `StrokePlayEngine.playerRange` is `1...8`.

---

## 2. Non-goals (this design)

- **Watch solo rounds.** `WatchQuickStartView` keeps its own flow; nothing here changes it.
- **Putts, fairways, GPS, or any new per-hole stat.** Solo makes these tempting; they are a
  separate feature with their own storage and screens.
- **Solo games.** `StablefordEngine.playerRange` stays `2...8`. A points-against-par game for one
  player is a real idea and not this one.
- **Renovating the group flow** beyond the player-count screen (§4.1), which changes for
  everybody by necessity.

---

## 3. What makes a round solo

```swift
extension RoundRecord {
    /// A round with a single seat. Solo is a shape, not a stored mode — nothing in the schema
    /// records it, and a solo round syncs and merges exactly like any other.
    public var isSolo: Bool { orderedSeats.count == 1 }
}
```

Inferred rather than flagged. No schema change, no migration, and nothing new for `SyncMerger` to
reconcile. This is safe because one seat has exactly one meaning: after §4.1, the only way to
reach it is to deliberately choose "Just me" on the player-count screen.

`NewRoundModel.playerCount`'s clamp becomes `max(1, min(8, newValue))`.

---

## 4. Setup

Solo reuses the existing builder rather than forking a parallel one. `NewRoundModel.makeRound`
stays the single place a round is constructed.

### 4.1 The player-count screen

`PlayerCountStep` is rebuilt: **1–8 as tappable targets, no stepper and no Next button.** A tap
commits the count and advances. This replaces up to four ± taps plus a Next tap with one tap, for
group rounds as well as solo.

Layout — solo as a hero row, group counts beneath it:

```
Step 2 of 6
How many players?
Tap to continue

┌──────────────────────────────────────┐
│  (⛳)  Just me                      › │
│        Solo round · no games          │
└──────────────────────────────────────┘

OR A GROUP

┌────┐ ┌────┐ ┌────┐ ┌────┐
│  2 │ │  3 │ │  4 │ │  5 │
└────┘ └────┘ └────┘ └────┘
┌──────────┐ ┌──────────┐ ┌──────────┐
│    6     │ │    7     │ │    8     │
└──────────┘ └──────────┘ └──────────┘
```

Seven group chips across a four-column grid would leave a ragged final row, so the second row is
three equal chips filling the width. Returning to this screen shows the current count selected;
advancing destroys nothing, since seats are only built when the round starts.

### 4.2 Steps a solo round skips

`NewRoundModel.activeSteps` gains solo cases. With `seats.count == 1`:

| Step | Solo | Why |
|---|---|---|
| `course` | shown | |
| `playerCount` | shown | where solo is chosen |
| `knownPlayers` | **skipped** | the one seat is you |
| `fillRemaining` | **skipped** | nothing left to fill |
| `strokes` | **skipped** | strokes are relative; there is nobody to give or receive |
| `holes` | shown | front 9 / back 9 / 18 |
| `games` | **skipped** | no game supports one player, and none is wanted |
| `bestBallTeams` | skipped | already conditional on Best Ball |

So: **course → players → holes → Start Round.**

The step counter is dropped once solo. Choosing "Just me" on *Step 2 of 6* and landing on *Step 3 of
3* shows a total shrinking under the user; `activeSteps` computes it correctly but it reads as a
glitch. `RoundBuilderStepHeader` gains a mode that renders the title without "Step N of M".

In practice this affects exactly one screen. The player-count step is reached before solo is chosen,
so it still shows "Step 2 of 6" as drawn in §4.1; only the holes step that follows a "Just me" tap
renders without a counter. The group flow keeps its counter throughout.

### 4.3 Who the solo player is

The seat is the player recorded at onboarding — `UserDefaults` key `myPlayerID`, already written by
`OnboardingFlowView.complete(with:)` and already read by `NewRoundFlowView.autoAssignMe()`.

If that record is missing — deleted from the Roster, or an install predating onboarding — solo
creates a `PlayerRecord` named "Me" with no handicap index, stores its id under `myPlayerID`, and
carries on. Solo self-heals rather than dead-ending, and a user who wants a handicap on it can set
one in the Roster.

### 4.4 Handicap settings

Solo rounds set `HandicapSettings(mode: .full, allowancePercent: 100, maxStrokes: nil)` explicitly.

This matters and is easy to get wrong. `HandicapSettings.default` is `.offTheLow`, which subtracts
the lowest handicap in the round from everyone. With one seat you *are* the low, so you would
receive zero strokes on every hole and net would silently equal gross — a permanently dead column
on the scorecard with no visible cause. `.full` is what the enum's own documentation prescribes for
stroke play.

---

## 5. Scoring

### 5.1 `ScoreGridView`

A new sibling to `ScoreStripView`: a fixed **1–11 grid plus a More cell**, twelve cells in four
rows of three, filling the space three other players used to occupy.

- **Fixed, not par-centred.** The numbers never move, so "5" is the middle of row two on every hole
  of every course and the grid becomes muscle memory. Only the par outline moves. A par-centred
  range would keep every cell useful but shift every number hole to hole, and would push an
  albatross behind the overflow.
- The par cell carries a green outline and a small `PAR` tag; the selected cell fills with the
  under/at/over-par color `ScoreStripView` already uses, judged against **net** par exactly as
  today.
- **More** presents a short sheet with a wheel picker starting at 12, over the still-visible grid.
  Rare enough that flick-and-confirm costs nothing, and it means no score is unreachable.

Cells are roughly four times the area of today's chips, and nothing scrolls — which is the real win
over the carousel. The carousel's problem was never chip size; it was that the number you wanted
could be off-screen.

Scoring stays **tap-then-Next**. Entering a score does not auto-advance the hole.

### 5.2 What the solo hole screen drops

The player name row, the team badge, the `+1 stroke` eyebrow, the leader line, the Wolf line, all
declaration prompts, and the "1 of 1 entered" counter. With one player, every one of them is either
constant or empty.

### 5.3 The header

`HoleHeader`'s centre slot — today the leader or Wolf line — carries the running score:

```
   PAR                +3                HANDICAP
    4               THRU 6                  7
```

Computed as gross on holes actually played minus par on those same holes, following the convention
`RoundSummaryView.finalScores` already established, so a round abandoned after four holes doesn't
report a course record. Gross, not net — the number you glance at while playing is the number on
the card.

The stroke index stays: it is what tells you which holes your strokes fall on, which the scorecard's
net row depends on.

### 5.4 Refactoring `HoleScreenView`

`HoleScreenView.swift` is 760 lines holding five private view types. Adding a second full input
layout by branching inside it would make an already-overlarge file worse, so it splits along the
seam this feature exposes:

| File | Holds |
|---|---|
| `HoleScreenView.swift` | container: hole paging, finish and incomplete-hole logic, undo, jump sheet, idle timer |
| `HoleHeaderView.swift` | `HoleHeader`, with the centre slot generalised to take either a leader/Wolf line or the running score |
| `HoleNavigationBar.swift` | `HoleNavigationBar`, `TrailingIconLabelStyle` |
| `HoleJumpSheet.swift` | `HoleJumpSheet`, `IncompleteHoleBanner` |
| `GroupScoreEntry.swift` | seat rows, `ScoreStripView` usage, Wolf/press/hole-event prompts |
| `SoloScoreEntry.swift` | `ScoreGridView` usage |
| `Scoring/ScoreGridView.swift` | the grid and its overflow sheet |

Pure extraction: the container's paging, completion and finish logic is shared by both layouts and
does not change. `requiredEntryCount`/`enteredEntryCount` already return 1 and 0-or-1 for a solo
round with no hole-event games, so the finish gate works unmodified.

---

## 6. Tabs

`RoundTabsView` omits Standings when `round.isSolo`:

| | Group | Solo |
|---|---|---|
| In progress | Hole · Scorecard · Standings | **Hole · Scorecard** |
| Complete | Summary · Scorecard · Standings | **Summary · Scorecard** |

Standings solo would be `RoundDashboardView`'s single plain-stroke-play row — a whole tab for one
line, whose one useful number now lives in the hole header. `FullScreenScorecardView` needs no
change: its grid is one row per player, so one player is one row, and it carries the net figures.

---

## 7. Finishing

### 7.1 Celebration

`CelebrationCenter.celebrate(_:)` already takes the word, so only the choice of word changes.
`HoleScreenView.completionWord` keys off money; solo keys off score against par:

| Score vs. par | Word |
|---|---|
| under | `FIRED` |
| even | `LEVEL` |
| +1…+9 | `SOLID` |
| +10 or worse | `WRAPPED` |

### 7.2 Solo summary

`RoundSummaryView` gains a solo branch — money rows, Settle Up, and the game-name subtitle are all
empty solo. It shows:

1. **Score hero** — gross, vs. par, net, and holes played if partial.
2. **Round shape** — counts of eagles-or-better, birdies, pars, bogeys, doubles, and worse; best
   and worst hole. All derived from scores already in the event log against course par. No new
   storage.
3. **The history line** (§7.3).

Share stays, with `RoundShareContent`'s settlement text replaced by the score for a solo round. The
scorecard image is unchanged.

### 7.3 History comparison

One line, from a query over rounds already stored:

- completed (`completedAt != nil`), not deleted
- same `courseID` **and** same `holeSegment`
- contains a seat with your `playerID` — **group rounds count**, since your gross is your gross
- played the full segment; partial rounds are excluded from both sides
- excluding the round just finished

From that set, comparing gross:

| Case | Line |
|---|---|
| no prior rounds | *(nothing shown)* |
| best ever there | "Your best at Pine Ridge." |
| otherwise | "3 better than last time · best there is 78." |

Deliberately one line and no new screen. Cross-tee and cross-course comparison, trends over time,
and a stats section are all out of scope.

---

## 8. Testing

Engine (`swift test` in `Packages/RoundPlayEngine`) needs no new cases — no engine behavior
changes. New tests go in `RoundPlayTests/AppModelTests.swift`, Swift Testing style, against an
in-memory `ModelContext`:

- `RoundRecord.isSolo` is true for one seat, false for zero and for two.
- A solo round built through `NewRoundModel` has `.full` mode at 100% with no cap — the §4.4 trap,
  and the one most likely to regress silently.
- With a nonzero handicap, a solo round's net differs from gross on the holes the strokes fall on.
- `activeSteps` for a solo model is exactly `[course, playerCount, holes]`, and `[course,
  playerCount, knownPlayers, fillRemaining, strokes, holes, games]` for a four-player one.
- `playerCount = 1` sets one seat; the clamp still refuses 0 and 9.
- The solo seat resolves to the `myPlayerID` player; with that key absent, a "Me" player is created
  and the key written.
- Running score is gross-minus-par over played holes only — a 4-hole solo round reads `+2`, not
  `−50`.
- History comparison: excludes partial rounds, other courses, other segments, and the current
  round; includes group rounds containing the player; returns nothing on a first round.

---

## 9. Open questions

None blocking. Two things deliberately left as decided rather than optional: solo drops the step
counter (§4.2), and history counts group rounds (§7.3).
