# Apple Watch Companion — Design

**Date:** 2026-08-15
**Status:** Draft, pending review

---

## 1. Premise

RoundPlay's whole pitch is that scorekeeping shouldn't need a phone out of your pocket. An Apple
Watch app takes that further: start a round, enter every player's score on every hole, check
standings and the scorecard, and settle the group's bets — all from the wrist, phone left in the
bag.

**Standalone, not just a remote control.** The watch keeps its own local copy of the round and
can score a full 18 holes with the phone off entirely. Phone and watch reconcile opportunistically
whenever they're back in Bluetooth range — there is no server in the loop yet.

**Scope of this pass: one person's phone and their own watch.** A group where multiple players
each carry their own phone or watch, all writing to the same round, is a materially different
problem (no shared clock, no shared arbiter, devices rarely in range of each other) and is
explicitly deferred — see §8.

---

## 2. Non-goals (this design)

- Multi-player device sync — other players' own phones/watches writing to the same round. See §8.
- Cloudflare backend / multi-device-over-internet sync. The original design's Phase 2 is still not
  built; this work is structured so that backend can slot in later without another redesign (§6),
  but it is not built now.
- Shot detection / GPS shot tracking. Documented as a future idea in §8, not designed here.
- New course entry or new player creation on the watch. Both stay phone-only — a course needs 18
  holes of par and stroke index typed in, and a new player needs a real name captured once,
  neither of which belongs on a 41mm screen.
- Settle Up / money movement flows on watch (§7 lists what's phone-only and why).

---

## 3. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Data on watch | Independent local SwiftData store, same schema as the phone | The "no phone at all" requirement means the watch must be able to read and write a round with zero connectivity |
| Shared schema | New `RoundPlayData` Swift package holds the `@Model` types, linked by both app targets | One schema, no drift — same reasoning as `RoundPlayEngine` already being a package |
| Transport | `WatchConnectivity`, using `transferUserInfo` | Queued, reliable, delivered even if the other side isn't reachable right now or the app isn't running — matches "opportunistic" |
| Sync unit | Whole-record union-merge, not incremental event streaming | A round's full event log is a few hundred small events; resending everything each time is cheap and trivially idempotent (union by UUID), with no gap-filling or replay logic needed |
| Conflict resolution | Per (hole, player) key, latest `recordedAt` wins; `id` breaks exact ties | Same fold rule as today (`RoundState`), just reordered on wall-clock time instead of a per-device counter that two writers would collide on |
| Round creation on watch | Quick-start only: existing course, roster players only, stake quick-picks, defaults copied from the last round with the same player group | Full setup doesn't fit a watch screen; this covers "start round from the wrist" for the common case of a repeat foursome |
| Game coverage | All six games at launch, including Wolf's partner picker and Bingo Bango Bongo's event buttons | Requested explicitly; each renders as its own screen in the entry sequence, same `requiredInputs`-driven pattern the phone already uses |

---

## 4. What already exists that this reuses directly

| Piece | Where | Why it transfers |
|---|---|---|
| `RoundState` | `RoundPlayEngine` | Pure fold of an event log to current values — platform-agnostic, compiles for watchOS unchanged except the ordering fix in §6 |
| Six game engines + `GameLibrary` | `RoundPlayEngine` | Pure functions, no I/O — settle the same way on watch as on phone |
| `requiredInputs`-driven hole screen pattern | `HoleScreenView.swift` | The watch's hole entry reuses the same idea (render prompts from the union of active games' declared inputs), just paginated one input at a time instead of one hole-screen-with-everything |
| Append-only `ScoreEvent` log, corrections-not-overwrites | `ScoreEvent.swift`, `RoundState.swift` | This is exactly the property that makes merging two independently-scored logs safe — nothing is ever destroyed, so union is always correct |

---

## 5. Architecture

### 5.1 Shared data package

`Packages/RoundPlayData/` (new), depending on `RoundPlayEngine`. Moves the `@Model` types that a
round actually needs on watch out of the `RoundPlay` app target:

`PlayerRecord`, `CourseRecord`, `FavoriteCourseRecord`, `RoundRecord`, `SeatRecord`,
`GameInstanceRecord`, `ScoreEventRecord`, and `RoundPlaySchema`.

`GuestNickname` and `AppearancePreference` stay iOS-only — placeholder-name generation doesn't
apply (watch only ever picks real roster players) and appearance preference is a phone settings
concern.

Both `RoundPlay` (iOS) and the new `RoundPlayWatch` (watchOS) targets link this package and each
own their own `ModelContainer` backed by their own on-disk store — two independent SwiftData
databases, not a shared file. `RoundPlayColors` isn't moved: it leans on UIKit dynamic `UIColor`
trait-collection colors that don't exist on watchOS. The watch app gets its own small, static
palette (§7.5) — same look, no shared token file, because the underlying color APIs genuinely
differ per platform.

### 5.2 Fixing the ordering scheme

Today, "current value for (hole, player)" is "highest `sequence` wins," where `sequence` is a
counter one device increments locally (`RoundRecord.nextSequence`). That's correct with one
writer. With two independent devices both appending to the same round, their counters can both
produce sequence 12 for two different events, and the existing tiebreak (comparing UUID strings)
would pick between them arbitrarily — not "whichever was actually entered later."

**Change:** `ScoreEventRecord` already stores `recordedAt: Date` — it just isn't threaded through
the `engineEvent` bridge into the pure `ScoreEvent` today, so the engine has no access to it.
Two changes:

```swift
// ScoreEvent (engine) — new field, and the bridge in ScoreEventRecord now passes it through
public let recordedAt: Date // wall clock at the moment it was entered

// ScoreEventRecord (SwiftData) — one new field
var deviceID: UUID // which physical device produced this event
```

`RoundState`'s fold changes from ordering by `(sequence, id)` to ordering by `(recordedAt, id)` —
same "latest wins, id breaks exact ties" shape, just keyed on a value that's comparable across
devices. `AuditLogView`'s newest-first sort changes the same way, so the audit trail reads in true
chronological order once two devices' entries are interleaved.

`sequence` stays on the model (harmless, still gives per-device local ordering) but stops being
load-bearing for merge or display order.

`deviceID` is a `UUID` minted once per install (phone and watch each mint their own) and persisted
in `UserDefaults`. It isn't part of the sort key — `recordedAt` plus `id` already gives a total
order — it exists for attribution: "entered on your watch" vs. "entered on your phone" is useful
context to eventually surface, and it's the seam a future multi-writer design would need. It stays
on the SwiftData record only; the pure engine doesn't need it to fold correctly.

### 5.3 Sync protocol

A round syncs as three independent channels, each a full-collection union-merge:

1. **Roster** (`PlayerRecord`) — phone → watch only. Players are only ever created/edited on the
   phone. Pushed whenever the roster changes.
2. **Courses** (`CourseRecord`, favorites + recently played) — phone → watch only, same reasoning.
   Not the whole course catalog — just what quick-start plausibly needs.
3. **Rounds** (`RoundRecord` + its `SeatRecord`/`GameInstanceRecord`/`ScoreEventRecord`) —
   bidirectional. The active round, plus the last few completed ones (so "copy settings from a
   previous round with the same players" works from watch without the phone).

Merge algorithm, run whenever a payload arrives: union each collection by `id`, insert anything
missing into the local `ModelContext`, save, refold `RoundState`. Because every record is
immutable once written (events are append-only; seats/games are fixed at round creation) union is
always correct — there's nothing to reconcile field-by-field, only "do I have this row yet."

### 5.4 Transport

`WCSession`, one thin wrapper per platform (`RoundSyncSession` on each side) around:

- `transferUserInfo(_:)` — the actual payload (JSON-encoded snapshot of the changed
  collection). Queued by the OS, delivered when reachable, survives the app being relaunched or
  the watch being out of range for hours. This is the one primitive that matches "opportunistic."
- `session(_:didReceiveUserInfo:)` — hands the payload to the merge function in §5.3.
- Reachability/activation state feeds the same three-state connection indicator the original
  design already specified for phone↔server sync (Live / Syncing / Offline, §3.4 of the main
  design doc) — reused verbatim as the visual language for phone↔watch, on both screens.

`updateApplicationContext` is deliberately not used for round data — it silently drops a payload
that hasn't been delivered yet if a newer one is queued, which is wrong for anything we can't
afford to lose. (It may still be fine for a cheap "is the other side alive" heartbeat, but that's
an implementation detail, not a design decision.)

### 5.5 Future: Cloudflare drop-in

This is the part that has to not need a redesign later. When the Phase 2 backend exists:

- The Durable Object becomes a fourth sync peer for the "rounds" channel, alongside phone and
  watch, using the same union-merge — it just also assigns an authoritative `serverSequence`.
- `ScoreEvent` gains `serverSequence: Int?`. The fold's comparator becomes "prefer
  `serverSequence` when present, else `recordedAt`" — a small, isolated change to one comparator,
  not a new event shape.
- Roster/course channels point at D1 instead of (or in addition to) the phone.

None of this is built now — it's stated here so the phone↔watch work doesn't box it out.

---

## 6. UX flows

### 6.1 Quick-start round (watch)

1. **Course** — pick from recently played / favorites (synced list, §5.3). No search, no entry.
2. **Players** — pick from roster only. If the same set of players (order-independent) has played
   a round before, that round's games, stakes, and handicap settings are offered as one tap:
   *"Same as Saturday — Skins $2, Nassau $5"*. Declining drops to a shorter manual pass.
3. **Games + stakes** — if not copying a previous round: pick games from a short list (same six),
   each stake set from quick-select presets (e.g. $1 / $2 / $5 / $10 / custom-on-phone-only).
   No new config knobs beyond stake on watch — anything more exotic (automatic press rules, team
   assignments, points tables) stays a phone-only edit, reachable later from the phone without
   breaking the round already in progress.
4. Round starts on the watch, seat handicaps copied from `PlayerRecord`, first hole ready.

### 6.2 Hole entry (watch)

One decision per screen, Digital Crown as the primary input:

- **Score screen**, one per seat: name, crown scrolls a number centered on the hole's par (same
  "centered on par" idea as the phone's carousel), tap or crown-detent to confirm, auto-advances
  to the next seat. A compact "2 of 4" indicator up top; swipe back to correct the previous
  player without losing your place.
- **Wolf's partner prompt** and **Bingo Bango Bongo's three event buttons** insert as their own
  screen(s) in that same sequence, before or alongside scores exactly as `requiredInputs` dictates
  on the phone — the watch view doesn't know what Wolf is, same as `HoleScreenView` today.
- Advancing past the last seat moves to the next hole. Corrections: tap back into a seat's screen
  from the compact per-hole summary; this appends a new event, never overwrites (§4).

### 6.3 Standings & scorecard (watch)

- **Standings** — a paged list, one game per page, mirroring `RoundDashboardView`'s per-game
  settlement and its explanation strings, trimmed to what fits: leader, money, one-line "why."
  Plain stroke play (no games running) shows net-to-par, same as today.
- **Scorecard** — not the full 18-column grid (doesn't fit); a focused view of the current hole
  plus the last few, scrollable by crown. The full paper grid stays a phone/landscape thing —
  explicitly one of the "not everything needs to be visible here" cuts.

### 6.4 Connection state (watch + phone)

Same Live / Syncing / Offline treatment as the main design's phone↔server section, shown as a
small glyph in the corner of every watch screen showing round data — never a full-screen blocker.
Offline is normal on a golf course and must never read as broken.

---

## 7. What stays phone-only, and why

| Feature | Stays on phone because |
|---|---|
| New course entry | Needs 18 rows of typed par + stroke index |
| New player creation | Needs a real typed name, once, per the app's "no Guest 3" rule |
| Settle Up / ledger detail | Stubbed even on phone today (§7 of the main design); watch gets a glance at "you're up $14 on Dave," nothing transactional |
| Full audit log | Watch shows recent entries inline; the complete "every entry, who, when" table stays a phone screen |
| Exotic game config (presses, teams, points tables) | Quick-select stakes only on watch; anything with more knobs is a phone edit |
| Full 18-column scorecard grid | Doesn't fit a watch face; watch shows current + recent holes only |

---

## 8. Future (documented, not designed here)

- **Multi-player device sync.** Every player scoring from their own phone or watch, with no
  central server, is a genuinely different problem — no two devices share a clock the way
  phone+watch effectively do (paired, time-synced by the OS), and a foursome's devices are rarely
  in Bluetooth range of each other mid-hole. It likely needs either local peer discovery
  (`MultipeerConnectivity`) that only reconciles reliably when the group clusters at each tee box,
  or the Cloudflare backend pulled forward. Worth its own design pass once phone↔watch sync is
  proven.
- **Shot detection.** Competing golf apps offer swing/shot detection via the watch's motion
  sensors, but only for a single player wearing the device — it can't attribute a shot to anyone
  else in the group. RoundPlay's whole premise is scoring the whole group, so this is a real gap
  in what "shot detection" could mean here; documented as a future idea, not committed to a phase.

---

## 9. Testing

**Engine (unit, `RoundPlayEngine`):**

| Case | Expected |
|---|---|
| Two events, same (hole, player), different `recordedAt` | Later `recordedAt` wins |
| Two events, identical `recordedAt`, different `id` | Deterministic (id-ordered) winner, stable across runs |
| Merge: log A ∪ log B, where B is a superset of A plus one new event | Fold result matches folding B alone |
| Merge: log A ∪ log B, disjoint new events on different holes from each device | Fold reflects both |
| `AuditLogView` ordering | Reads newest-first by `recordedAt`, not `sequence` |

**Sync (unit, `RoundPlayData`):**

| Case | Expected |
|---|---|
| Merge two `RoundRecord` snapshots with overlapping events | Union, no duplicates, no crash on already-known ids |
| Merge where one side has a seat/game the other doesn't | Result has both |
| Repeated merge of the same payload (delivery retried) | Idempotent — no duplicate rows |

**Manual, two physical devices:**

- Airplane-mode the watch, score three holes, restore connectivity — phone catches up.
- Score simultaneously on phone and watch for different holes — both converge to the same
  standings once synced.
- Score the *same* hole/player from both devices within the same minute — later wall-clock entry
  wins on both sides after sync; no crash, no duplicate row in the audit log.
- Full round started and played entirely on watch, phone untouched and off, then powered on —
  phone shows the finished round correctly.

---

## 10. Phasing

Each phase gets its own implementation plan.

| Phase | Scope | Exit criterion |
|---|---|---|
| **A — Foundation** | Extract `RoundPlayData` package; add `deviceID` and thread `recordedAt` through to the event model; update `RoundState` fold and `AuditLogView` ordering; multi-device fold/merge fixtures | iOS app builds and behaves identically; new ordering tests green alongside all existing engine tests |
| **B — Sync plumbing** | New watchOS target scaffold; `WCSession` wrapper; roster/course/round sync channels; connection-state indicator | Create a round on phone, watch has a full copy shortly after; score on watch in airplane mode, phone catches up on reconnect |
| **C — Scoring on watch** | Hole entry (all six games' inputs), standings, focused scorecard view | A full round can be played start-to-finish scoring entirely from the watch, phone never opened, standings agree after sync |
| **D — Round creation on watch** | Quick-start flow: course pick, roster-only players, stake presets, copy-from-previous-round | A brand-new round can be started from the watch alone, first hole ready to score, no phone interaction |

This immediate plan covers **Phase A only** — it's the foundation everything else depends on and
is cleanly testable in isolation (engine + data layer, no UI, no watch target yet).

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| Ordering change is a correctness-critical rewrite of the same fold every game engine depends on | Extensive fixture coverage before touching UI (§9); all 88+ existing engine tests must stay green |
| SwiftData models compiling identically across iOS and watchOS `ModelContainer`s | Verify early in Phase A/B — cross-platform SwiftData is well-supported, but this is the first time this codebase links a package into two different platform targets |
| Watch battery/storage limits for holding several rounds' history | Rounds channel only syncs the active round plus a handful of recent ones (§5.3), not the whole phone history |
| Crown-driven score entry proving fiddly in practice (gloves, cart bumps) | Prototype and test on a physical device early in Phase C before committing to it as the only input method |
