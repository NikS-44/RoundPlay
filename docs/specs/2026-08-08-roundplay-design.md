# RoundPlay — Design

**Date:** 2026-08-08
**Status:** Approved design, pending implementation plan

> **Note:** `/Users/nik/workplace/RoundPlay/` is not yet a git repository. `git init` it and
> commit `docs/` as the first commit of the new project.

---

## 1. Premise

RoundPlay is a native iOS app for tracking the betting games golfers play on the course.
A group starts a round, picks one or more games, enters scores hole by hole, and sees a
live standings dashboard with money owed. Sessions are shared by QR code or a spoken
join code so anyone in the group can follow along.

The differentiating bet is **onboarding**: joining a round and entering a score must be
effortless for a 70-year-old standing on a tee box in the sun. Every design decision below
is subordinate to that.

**Domain:** `roundplay.app`

### Non-goals (phase 1)

- Web client (designed for, built later)
- Holding, transmitting, or taking a cut of user funds — see §7
- GPS, shot tracking, rangefinding
- Licensed course database
- Social feed, leaderboards across groups, handicap certification

---

## 2. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Codebase | Fresh Xcode project; port UpKeepr's design system, Kokoro TTS, app shell | The thing being replaced (CloudKit/SwiftData-as-truth) is the most deeply woven part of UpKeepr |
| Identity | Progressive: anonymous device token → claimed by Sign in with Apple **or** Google | Joiners never hit an auth wall; both providers work on iOS and web |
| Names | Every seat requires a name; host may pre-add players | No "Guest 3" |
| Sync | Offline-first append-only event log + WebSocket fast path | One design satisfies audit log, offline, and live standings |
| Scorekeeping | Single scorekeeper encouraged, multi-entry permitted, all entries attributed | Matches how groups actually keep score |
| Course data | User-entered par + stroke index, shared globally | Unlocks net play for ~one screen; crowdsources what a vendor would charge for |
| Handicaps | Captured at player registration, applied per hole by stroke index | Mixed-skill groups are the norm; without strokes the game isn't fun |
| Score input | One screen per hole, tap-a-number rows | It *is* the paper scorecard — a mental model users already have |
| Join code | Three dictionary words, e.g. `otter-maple-jump` | Relayable out loud, self-correcting, more entropy than 8 digits |
| Backend | Cloudflare Workers + D1 + Durable Object per round | A round is exactly the DO shape: bounded, stateful, few concurrent writers |
| Payments | Ledger only, no custody, stubbed in phase 1 | Stripe prohibits the category and doesn't do P2P — see §7 |

---

## 3. Architecture

### 3.1 Backend (Cloudflare)

| Piece | Responsibility |
|---|---|
| **Durable Object** (one per round) | Authoritative round state. SQLite-backed append-only event log, serialized writes, WebSocket hibernation for live push, alarm for lifecycle transitions. |
| **D1** | Everything outliving a round: accounts, player roster, courses, round index, join-code resolution, ledger balances. |
| **Workers** | HTTP API — create round, resolve join code, course CRUD, roster, sync fallback when the socket is down. |

No R2 or KV in phase 1.

### 3.2 iOS

SwiftUI + Observation, matching UpKeepr's idiom. **The Durable Object is the source of
truth; SwiftData is a local cache plus an outbox.** This inverts UpKeepr, where SwiftData
is truth and CloudKit mirrors it. The inversion is what lets a non-iPhone user on the web
see the same round. CloudKit is not used anywhere.

### 3.3 Sync protocol

Every score is an append-only event:

```
ScoreEvent {
  roundID, hole, playerID, kind, value,
  enteredBy (accountID), deviceID,
  clientUUID,        // idempotency — prevents flaky-connection double-posts
  clientTimestamp,
  serverSeq          // assigned by the DO, authoritative ordering
}
```

Client appends locally and renders immediately, queues in the outbox, pushes when it can.
The DO assigns `serverSeq` and broadcasts to connected sockets. On reconnect a client
requests everything after its last known `serverSeq`.

Three properties fall out of this single decision:

- **Audit log is free** — it is the event log read forward. "Dave changed your 6 to a 5 on
  14" is a query, not a feature.
- **Offline is free** — a dead zone is a client with a long outbox.
- **Conflicts are trivial** — current value for a `(hole, player, kind)` is the highest
  `serverSeq` event. Nothing is destroyed, so nothing needs merging.

Corrections **append**; they never overwrite. Silent edits are impossible by construction.

### 3.4 Connection state (explicit UI requirement)

The scorecard header shows one of three states at all times. Users must never believe a
score synced when it did not.

| State | Meaning | Treatment |
|---|---|---|
| **Live** | Socket open, outbox empty | Subtle — a small filled dot |
| **Syncing** | Reachable, outbox draining | Progress affordance, count of pending |
| **Offline** | Unreachable | Persistent banner: "Offline — 6 scores will sync when you have signal." Non-dismissable. |

### 3.5 Identity and join codes

First launch mints an anonymous device token server-side. Signing in later *claims* that
token and everything it did. Joiners never see auth.

**Providers: Sign in with Apple and Google**, on both iOS and web.

*Verification is server-side, always.* Both providers issue a signed JWT; the Worker
verifies it against the provider's JWKS (`appleid.apple.com/auth/keys`,
`www.googleapis.com/oauth2/v3/certs`) and checks `iss`, `aud`, `exp`, and nonce. No SDK
needed — WebCrypto in a Worker is sufficient. The client never asserts its own identity,
which is what lets iOS and web share one auth path.

*App Store compliance:* Guideline 4.8 requires that an app offering a third-party login
also offer an equivalent privacy-preserving option. Shipping Sign in with Apple alongside
Google satisfies this. Apple must not be the *only* option on web, and Google must not be
the only option on iOS — offering both everywhere is the simple compliant answer.

**Two provider-specific traps, both of which cause data loss if missed:**

1. **Apple returns the user's name and email only on the *first* authorization.** Never
   again, on any subsequent sign-in. It must be captured and persisted at that moment or
   it is gone permanently.
2. **Apple's private relay makes email useless as a join key.** A user who signs in with
   Apple may present `xyz@privaterelay.appleid.com` while the same human signs in with
   Google as `bob@gmail.com`. These cannot be matched, and matching on email where they
   *do* collide is an account-takeover vector when the provider's email is unverified.

**Therefore: never auto-merge accounts by email.** An Account owns many `AuthIdentity`
rows, linked *explicitly* — a signed-in user chooses "add another sign-in method" and
completes that provider's flow. Signing in with an unlinked provider creates a new Account,
and the recovery path is an explicit merge the user initiates, not a silent guess.

**Join code lifecycle** — the 48-hour boundary is a permission change, not just an expiry:

| Window | Code grants |
|---|---|
| 0–48h | Join a seat + enter scores |
| 48h – 1 month | View only (settle up, review, no edits) |
| after 1 month | Dead |

This bounds the window in which someone can claim a seat and touch money to 48 hours,
while keeping a shared link useful for a month.

**Format:** three words from a curated 2,048-word list → 8.6 billion combinations
(vs. 100 million for 8 digits). List curation rules: 3–6 letters, no homophones
(*beet/beat*), no near-twins (*brake/break*), nothing embarrassing. Static asset, one-time
authoring cost. Typing is autocompleted after 2–3 letters.

**One artifact, three ways in:** `roundplay.app/otter-maple-jump` is what the QR encodes,
what you text, and what you say out loud. A universal link opens the app if installed, the
web join page if not.

Code resolution is rate-limited per IP.

---

## 4. Data model

D1 unless noted.

| Entity | Fields (abbreviated) | Notes |
|---|---|---|
| **Account** | `id, displayName, isAnonymous, createdAt` | Anonymous until claimed. Holds no provider fields — those live in `AuthIdentity`. |
| **AuthIdentity** | `id, accountID, provider (.apple/.google), subject, emailAtLink?, nameAtLink?, linkedAt` | One row per linked sign-in method; an Account may have several. `(provider, subject)` is unique — **`subject` is the join key, never email.** `nameAtLink`/`emailAtLink` capture Apple's first-authorization-only payload. |
| **Player** | `id, ownerAccountID, name, handicapIndex?, linkedAccountID?, lastPlayedAt, playCount` | The recurring-companions roster; sorted by recency for one-tap re-add. May link to an Account, or never. |
| **Course** | `id, name, holes[18] {number, par, strokeIndex}, createdByAccountID` | Created by whoever plays it first, shared globally thereafter |
| **Round** | `id, courseID, joinCode, hostAccountID, status, createdAt, scoringClosesAt, expiresAt` | Index row in D1; live state in the DO |
| **Seat** | `roundID, playerID, name, handicapIndexAtRound, claimedByAccountID?` | Handicap frozen at round time so history stays reproducible |
| **GameInstance** | `roundID, gameType, config JSON, holeScope` | A round runs several at once — Skins + a Nassau is the normal case |
| **ScoreEvent** | see §3.3 | DO SQLite, append-only |
| **LedgerEntry** | `fromAccount, toAccount, amount, roundID, status` | Phase 5 |

### Handicap application

Course handicap distributes strokes by stroke index: a 12 handicap receives one stroke on
holes with SI 1–12; a 22 receives one on all 18 plus a second on SI 1–4. Net score per hole
= gross − strokes received. Applied **before** any game engine runs.

---

## 5. Game engine

Each game is a **pure function**: log in, settlement out. No I/O, no stored state, no
database access. Given the same log it always returns the same money — which matters more
here than in most apps, because a wrong settlement is the one bug that ends a friendship.

```swift
protocol GameEngine {
    associatedtype Config
    static var requiredInputs: Set<InputKind> { get }   // .strokes, .partnerChoice, .holeEvents
    static var playerRange: ClosedRange<Int> { get }
    static func settle(_ log: [ScoreEvent], seats: [Seat],
                       course: Course, config: Config) -> Settlement
}
```

`requiredInputs` is what lets the two awkward games fit without special-casing. Wolf
declares `.partnerChoice` and the hole screen grows a partner prompt; Bingo Bango Bongo
declares `.holeEvents` and it grows three event buttons. **The scorecard UI reads the
declaration and adapts — it does not know what Wolf is.**

`Settlement` carries a per-hole **explanation string**, not just a number:
*"Hole 7: Dave wins 2 skins ($20) — carryover from 6."* Every dollar traceable to a
sentence. This is what ends the 19th-hole argument.

### 5.1 Engine location — deliberate call

The engine is **Swift-only in phase 1**. The client computes standings so the dashboard
works with zero signal; the DO only stores events. When the web client arrives it needs a
TypeScript port.

Therefore, **from day one both share a JSON test-fixture suite** — a round's event log plus
its expected settlement. The eventual port is then *verified* against Swift behavior rather
than reimplemented from memory. Writing fixtures now costs almost nothing; skipping them
means the web client silently pays out different money than the app.

### 5.2 The six launch games

| Game | Players | Inputs | Primitive established |
|---|---|---|---|
| Skins | 2–8 | strokes | per-hole pot + carryover |
| Nassau | 2 or 4 | strokes | match play across segments + presses |
| Stableford | 2–8 | strokes | points vs par |
| Nines (5-3-1) | 3 only | strokes | fixed points distribution |
| Wolf | 3–5 (4 typical) | strokes + partnerChoice | rotating partners, per-hole state machine |
| Bingo Bango Bongo | 2–4 | holeEvents | non-stroke event input |

Coverage: six games, six reusable primitives, every group size from 2 to 8.

**Skins** — each hole is worth one skin at the unit stake. Lowest net score wins it
outright; a tie carries the pot to the next hole and it accumulates.

**Nassau** — three separate match-play bets at the unit stake: front 9, back 9, total 18.
Standard match play (holes up/down). *Presses:* a side that goes 2 down may start a new bet
on the remaining holes; automatic presses at 2 down are a config option. Singles (2) or
2v2 best ball (4).

**Stableford** — points against net par: double bogey or worse 0, bogey 1, par 2, birdie 3,
eagle 4, albatross 5. Point values configurable (Modified Stableford differs). Settles as
per-point or winner-takes-pot. Caps blowup holes, which is why it works for beginners.

**Nines (5-3-1)** — exactly 3 players; 9 points per hole. 5 low / 3 middle / 1 high. Ties:
all three tie → 3/3/3; two tie low → 4/4/1; two tie high → 5/2/2. Always sums to 9.
Settles on point differential × unit.

**Wolf** — order rotates each hole; the Wolf tees off first, then after each opponent's tee
shot may immediately claim that player as partner (must decide before the next player
tees). Declining everyone means Lone Wolf against the field. Wolf + partner win → 1 point
each; field wins → 1 point each; Lone Wolf wins → 4 points; Lone Wolf loses → 1 point to
each opponent. Point values configurable — variants are everywhere.
*18 holes does not divide by 4:* config option for holes 17–18 (lowest-points player is
Wolf, or Wolf ends after 16).

**Bingo Bango Bongo** — three points per hole, one each for first ball on the green
(bingo), closest to the pin once all balls are on (bango), and first in the hole (bongo).
Requires playing in order (farthest from hole first). Honor system, entered by the
scorekeeper. The strongest equalizer in the set — it rewards sequence, not skill.

---

## 6. UX flows

### 6.1 Create a round (host)

1. **New Round**
2. **Course** — recents, search, or add new (18 × par + stroke index; ~30 seconds off the
   physical scorecard, then shared globally forever)
3. **Players** — roster sorted by recency, one tap to add; "New player" requires a name,
   handicap optional
4. **Games** — pick one or more from the library; set the unit stake per game, or "no money"
5. **Create** → QR code, the three words, and a share sheet

### 6.2 Join (guest)

1. Scan the QR, tap the link, or type the words
2. **"Which one are you?"** — the seats the host pre-added, or *"I'm someone else"* → enter
   name
3. In the round

No account, no password, no email. The full path is: point camera, tap your name.

### 6.3 Score entry — the hole screen

The single most-repeated interaction: up to 72 entries per round, outdoors, in sun.

- **Header** — hole number, par, stroke index, connection state
- **Rows** — one per player: name, and a number strip **centered on the hole's par**. For a
  par 4: `3 4 5 6 7` plus an "other" overflow. Five thumb-sized targets covering ~95% of
  real scores; disasters still get in.
- **Game prompts** — rendered from `requiredInputs`. Wolf's partner picker appears before
  scores; BBB's three event buttons appear alongside.
- **Advance** to the next hole; running standings peek at the bottom.

### 6.4 Dashboard

Live standings per active game, money column when stakes are set, per-hole explanation
strings expandable. Separate **audit view**: every entry, who made it, when, and what it
replaced.

### 6.5 Voice

Kokoro (ported from UpKeepr) is **text-to-speech** — it talks, it does not listen. Used to
announce standings hands-free on the tee box: *"After 7, Dave leads with 3 skins."* No
squinting at a screen in the sun. **Phase 3.**

Voice *input* ("Bob had a five") is different technology — Apple's on-device speech
recognition — and would be a significant accelerant for §6.3. **Phase 4+, independent.**

---

## 7. Payments — analysis and stub

### 7.1 The finding

Two independent blockers make the originally-imagined model unworkable:

1. **Stripe prohibits the category.** Games of skill offering monetary prizes are on
   Stripe's restricted list; wagering generally is prohibited. A golf-wagering app taking a
   per-game rake risks account termination, not merely declined applications.
2. **Stripe does not do P2P.** Connect is built for marketplace flows (platform → seller),
   not friend → friend. Facilitating transfers between users is precisely what triggers
   **state money transmitter licensing** — roughly 49 states, six figures annually in bonds
   and compliance.

**Apple Pay does not route around this.** Apple Pay is a card-credential presentation
method, not a payment network; behind it sits a processor, so an Apple Pay web checkout
inherits every restriction above. Apple's own person-to-person transfers are Apple Cash,
which is Messages-only with no third-party API.

### 7.2 The model that works

The Splitwise pattern: **never touch funds.** Compute the net IOU ledger, simplify the debt
graph, and hand off to Venmo/PayPal/cash with amount and recipient pre-filled. Users settle
outside the app and mark it paid. No custody, no MTL, no restricted-business exposure.

**Consequence for monetization, and it is a real one:** this model has no natural place for
a $1–10 per-game rake, because no money flows through the platform. Revenue has to become
subscription, per-round unlock, or premium features. This is a change to the original
business plan and should be an explicit decision, not a default.

### 7.3 Phase 1 stub

The running tally is genuinely useful with zero payment infrastructure, so it ships early:

- Ledger computed and displayed throughout — "you're up $14 on Dave"
- **Settle Up** button present, **greyed out**, labeled *"Coming soon"*
- Data model carries `LedgerEntry` from the start so no migration is needed later

Explicitly **not** built, in any phase: holding funds, escrow, taking a percentage of a
transfer.

---

## 8. Phasing

This spec describes the whole program. It is **too large for one implementation plan** —
each phase gets its own plan and its own build cycle. The immediate plan covers
**phases 0 and 1 only**.

| Phase | Scope | Exit criterion |
|---|---|---|
| **0 — Scaffold** | New Xcode project; port `DesignSystem/` and rewrite the app shell (UpKeepr's `ContentView`/`AppDelegate` are CloudKit-bound and do not port). New color scheme. Kokoro ports in Phase 3 where it is first used; `NotificationService` when reminders exist. | App builds and launches with RoundPlay branding |
| **1 — Playable, local only** | Course entry, player roster, all six engines + fixture suite, hole screen, dashboard, ledger display (stub). SwiftData only, no backend. | One person can keep score for a foursome start to finish and get correct money |
| **2 — Multiplayer** | Cloudflare Workers + D1 + DO; join codes/QR/universal links; event sync, outbox, connection states; audit view; anonymous identity + Apple/Google claim with server-side JWT verification | Four phones in one round, one walks into a dead zone, everything reconciles |
| **3 — Polish** | Kokoro standings announcements, round history, player stats, accessibility pass (Dynamic Type, contrast in sun, VoiceOver) | Usable by the target demographic without help |
| **4 — Web** | Join + view + score entry on `roundplay.app`; Sign in with Apple JS + Google Identity Services against the same Worker auth path; TypeScript engine port verified against the phase-1 fixtures | Android user plays a full round from a browser |
| **5 — Settlement** | Net-debt simplification, deep links out to Venmo/PayPal, mark-as-paid, dispute trail | Group settles a real round |

Phase 1 is deliberately backend-free. The engines are the risky, fiddly part and the part
that must be exactly right; isolating them from network concerns gets them tested fastest.
The event-log shape works locally in SwiftData unchanged, so phase 2 adds transport rather
than rewriting storage.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| Engine correctness — wrong money is the worst possible bug | Pure functions, JSON fixture suite per game, explanation string for every dollar |
| Wolf is ~40% of engine effort for one game | Accepted knowingly; it is the demo that sells the app |
| Anonymous→claimed identity merge is genuinely fiddly, and two providers doubles the paths | Phase 2; anonymous token is the merge key. Apple + Google means one human can hold two Accounts and they **cannot** be reconciled by email (private relay). Requires an explicit user-initiated merge flow, not a silent guess. |
| Apple's name/email arrives only on first authorization | Persisted to `AuthIdentity.nameAtLink`/`emailAtLink` at that moment; add a fixture test that fails if the first-auth payload is dropped |
| Rule variants — every group plays Wolf/Stableford slightly differently | Config-driven point values from day one; do not hardcode |
| Monetization has no home in the no-custody model | Flagged in §7.2 as an open business decision |
| Sunlight legibility for the target demographic | Phase 3 accessibility pass is not optional |

## 10. Open questions

1. **Monetization model** — subscription, per-round unlock, or premium games? Required
   before phase 5, not before phase 1.
2. **Handicap source** — self-reported only, or eventually GHIN import? Self-reported for
   now.
3. **Round expiry semantics** — does a round's data delete at 1 month, or does only the
   *join code* die while history persists for participants? Recommend the latter.
