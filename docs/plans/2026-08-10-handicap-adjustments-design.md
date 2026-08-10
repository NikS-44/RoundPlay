# Handicap adjustments step — design

**Date:** 2026-08-10
**Status:** approved

## Problem

The round builder has no way to agree strokes. Every round gives every player their full course
handicap, allocated by stroke index. That is wrong for the games this app is mostly used for.

Golfers betting money on Skins, Nassau, Wolf or Match Play play **off the low**: the lowest
handicap plays off scratch and everyone else receives the *difference*. Giving everyone their full
handicap is not equivalent, because strokes land on stroke-index order:

> A=10, B=4, stroke index 3.
> Full handicaps: both receive a stroke — neither has an edge.
> Off the low (A gets 6): A receives a stroke, B does not — A has an edge.

So the current engine mis-scores every hole-by-hole money game. Fixing that is part of this work,
not a follow-up.

## Background: how strokes actually get agreed

Three numbers, commonly conflated:

1. **Handicap Index** — durable property of a player. Max 54.0.
2. **Course Handicap** — `Index × (Slope ÷ 113) + (Course Rating − Par)`. Per course and tee.
3. **Playing Handicap** — Course Handicap × a format allowance.

This app does not collect slope or course rating, so it treats a rounded index as the course
handicap. That is the standard casual approximation and is what a group agreeing strokes on the
first tee does anyway. This design does not change that.

Recommended allowances (USGA/R&A Appendix C):

| Format | Allowance |
| --- | --- |
| Individual match play | 100% |
| Individual stroke play / Stableford | 95% |
| Four-ball match play | 90% |
| Four-ball stroke play / Stableford | 85% |

Caps ("max 18", "nobody gets more than 8") are **not** in the rules. They are a house convention to
stop a very high handicap being unbeatable in Skins.

Most casual betting groups skip all of this and negotiate: *"you give me four."* That is off-the-low
with an agreed number, and it is the common case this step must make fast.

## Design

### Stroke mode — the primary choice

```
offTheLow   Lowest plays scratch, everyone else gets the difference.  (default)
full        Everyone plays their whole playing handicap.
straightUp  No strokes. Gross scores only.
```

`offTheLow` is the default because it matches how money games are played. `full` stays available
because it is correct for stroke play and Stableford. `straightUp` is one tap for groups of similar
ability.

### Computation pipeline

Applied in this order, then allocated by stroke index exactly as today:

1. Start from the seat's course handicap.
2. **Allowance** — `round(courseHandicap × allowancePercent / 100)`.
3. **Cap** — `min(value, maxStrokes)` when a cap is set. Caps the *playing handicap*, not the
   strokes received, so it composes predictably with the allowance.
4. **Mode** — `straightUp` zeroes everyone; `offTheLow` subtracts the lowest value in the round,
   floored at zero; `full` passes through.

Plus handicaps stay out of scope and clamp to zero, as they already do.

### Allowance and cap placement

Behind an "Advanced" disclosure, pre-filled from the games already chosen (85% four-ball, 95%
Stableford, 100% match play). A foursome betting $5 never sees a percentage; a group that runs a
proper game can find one.

### Per-player negotiation

The step lists each player with the strokes they will receive, tappable to override. An override is
an agreed number for this round — it does not recompute from an index.

### Saving to the roster

**Round-only by default.** "Nik gives Tilly 6 today" is a match arrangement; writing it to the
roster would silently corrupt every future round.

**One exception:** when a player has *no handicap index on file*, the estimate is new information
rather than an override, so the step offers to save it. This mirrors the existing "Save to Roster"
behaviour in `SeatEditSheet`.

## Scope

- Engine: `StrokeMode`, `HandicapSettings`, playing-handicap computation, threaded through
  `RoundState`. Tests covering the stroke-index divergence above.
- Persistence: mode / allowance / cap on `RoundRecord`, frozen at round creation like seats already
  are.
- App: new builder step after the player steps; `NewRoundModel` step numbering picks it up
  automatically.

Finished rounds re-score under the new rules. They are re-derived from the event log on read, and
the user chose correctness over preserving past numbers.
