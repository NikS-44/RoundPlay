# App Store Submission — RoundPlay 1.0

Everything App Store Connect will ask for, with a drafted value ready to paste. Anything needing
your decision is marked **DECIDE**.

**Date prepared:** 2026-09-05 · **Version:** 1.0 · **Build:** set automatically by fastlane

---

## 1. Before you open App Store Connect

| Check | Status |
|---|---|
| Bundle ID `app.roundplay.RoundPlay` registered to team `XVD9C7XLM5` | Already in `project.yml` and `fastlane/Appfile` |
| App record created in App Store Connect | **Not done — do this first** |
| App name "RoundPlay" available | **DECIDE / verify.** Cannot be checked from here. The name is reserved when the app record is created, so check early — if it's taken, everything below that says "RoundPlay" needs revisiting |
| 1024×1024 icon, no alpha | Present: `RoundPlay/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |
| Version 1.0 in the binary | Verified in the built `Info.plist` |
| iPhone-only | Verified: `UIDeviceFamily = [1]` |
| Privacy policy reachable | `https://roundplay.app/privacy` → 200 |
| Support page reachable | `https://roundplay.app/support` → 200 |
| Export compliance declared | `ITSAppUsesNonExemptEncryption = false` in Info.plist, so upload won't ask |

---

## 2. App information

| Field | Value |
|---|---|
| **Name** (30 max) | `RoundPlay: Golf Scorecard` (25) — **DECIDE**: plain `RoundPlay` is cleaner branding; the longer form is materially better for search, since nobody searches "roundplay" |
| **Subtitle** (30 max) | `One card for the whole group` (28) |
| **Primary category** | Sports |
| **Secondary category** | None. Leave empty rather than forcing a poor fit |
| **Content rights** | Contains third-party content: **Yes**. The bundled course database is OpenGolf data under ODbL, and the app already carries the required attribution on the course picker ("Course data from OpenGolf, ODbL licensed") |
| **Age rating** | See §5 |

### URLs

| Field | Value |
|---|---|
| **Privacy Policy URL** | `https://roundplay.app/privacy` |
| **Support URL** | `https://roundplay.app/support` |
| **Marketing URL** | `https://roundplay.app` |

### Pricing and availability

| Field | Value |
|---|---|
| **Price** | Free — matches the site's "Free while we're in beta, on iPhone" |
| **In-app purchases** | None |
| **Availability** | All territories. Nothing here is territory-restricted: the app has no payments and no gambling functionality (§5) |

---

## 3. Version information (what reviewers and users read)

### Promotional text (170 max — editable later without review)

```
Free while we're in beta. Keep the card for your whole group: every score, every game, handicaps
applied automatically. No account, no sign-up, and no signal needed.
```

### Description (4000 max)

```
RoundPlay keeps the scorecard for your whole group.

Put in each player's score on each hole and RoundPlay does the rest: it allocates handicap strokes
to the right holes, scores whichever formats your group is playing, and keeps a running total you
can check at any point in the round.

ONE SCREEN PER HOLE
Big, thumb-sized targets you can hit without looking, on a screen designed to be used standing on
a tee box in the sun. Correct a score any time; nothing is ever quietly overwritten, and every
entry is attributed, so the argument on the 19th ends with a look at the history instead of a
shrug.

PLAYING ALONE
Playing on your own gets its own stripped-down mode: one tap per hole, your score against par in
the header, and none of the group machinery in the way.

THE GAMES YOU ACTUALLY PLAY
Stroke Play, Match Play, Best Ball, Skins, Nassau, Stableford, Nines, Wolf, Bingo Bango Bongo and
Sixes — from two players to eight. Run more than one at once; a Skins game alongside a Nassau is
the normal case, not an edge case. Every format is scored properly, including carryovers and
presses.

HANDICAPS DONE RIGHT
Strokes land on the correct holes by stroke index, not spread evenly. Play off the low handicap or
off full handicaps, set an allowance, or agree a number out loud and enter it directly.

15,000+ COURSES, BUILT IN
The course list ships inside the app, so it works with no signal at all. Pars and stroke indexes
are already filled in. Can't find your course, or playing somewhere new? Add it by hand in a
minute.

THE CARD, WHEN YOU'RE DONE
A full landscape scorecard you can scroll hole by hole, a summary of how the round went, and a
picture you can share to the group chat.

NO ACCOUNT, NO TRACKING
There is no sign-up, no email, no password, and no server. Your rounds live on your iPhone and
nowhere else. RoundPlay contains no analytics, no advertising and no third-party code of any kind.

RoundPlay records who owes who when a group plays for something. It never holds, moves, or takes a
cut of money.
```

### Keywords (100 max, comma-separated, no spaces after commas)

```
golf,scorecard,scorekeeper,handicap,skins,nassau,stableford,wolf,nines,bestball,matchplay,round
```
95 characters. "golf" and "scorecard" are already in the name if you use the longer name — Apple
searches name, subtitle and keywords together, so consider swapping those two for `caddie,tee`
if you go with `RoundPlay: Golf Scorecard`.

### What's New in This Version

```
First release.
```

---

## 4. App Privacy — "Data Not Collected"

**Answer: the app collects no data.** In App Store Connect, choose **"No, we do not collect data
from this app"** and you are done — no data-type questions follow.

This is verified against the source, not assumed:

- No `URLSession`, no networking code of any kind anywhere in the app or its packages
- No third-party dependencies at all — the only packages are the local `RoundPlayEngine` and
  `RoundPlayData`
- The course catalog is a bundled JSON file, so even course lookup makes no request
- Location is requested once, in use, at reduced accuracy, used in memory to sort the course list,
  and never stored or transmitted. Apple only requires disclosure for data **collected**, meaning
  transmitted off device — this is not
- No analytics, attribution, advertising or crash-reporting SDK
- App Tracking Transparency is never requested, because nothing is tracked

Consistent with the published policy at `roundplay.app/privacy`.

---

## 5. Age rating, and the one real rejection risk

### The risk

RoundPlay scores games that groups play for money (Skins, Nassau, Wolf) and shows who owes whom.
A reviewer skimming the screenshots could read "gambling app" and reject under **guideline 5.3
(Gaming, Gambling, and Lotteries)**, which carries hard requirements the app can't and shouldn't
meet.

The distinction that matters: **RoundPlay never handles money.** No payments, no wallet, no IAP,
no payment processor, no wagering mechanism, no chance-based outcome. It does arithmetic on scores
the user typed in and displays a tally — the same thing a calculator or the back of a paper
scorecard does. Settlement happens between the players, outside the app.

**Two mitigations, both already in place:**
1. The App Review notes below state it explicitly.
2. The screenshots deliberately lead with scorekeeping, not money. The demo round in them has no
   money game running at all, so no dollar figures appear.

### Suggested answers

| Question | Answer |
|---|---|
| Gambling | **None.** No gambling functionality: no wagering, no chance-based outcomes, no money handling |
| Contests | None |
| Simulated gambling | No |
| Alcohol, tobacco or drug use | None |
| Everything else | None |

Expected result: **4+**.

**DECIDE:** this is a judgement call. If you'd rather not argue it, answering "Infrequent/Mild" to
simulated gambling lands you at 17+ and removes the question — at the cost of a rating that
misrepresents a scorekeeping app and shrinks your audience. My recommendation is to answer None
and let the review notes do the work; if Apple pushes back, raising the rating is a fast fix,
whereas starting at 17+ is hard to walk back.

---

## 6. App Review Information

**Sign-in required:** No. The app has no accounts — leave the demo account fields empty.

**Contact:** Nik Shah · `nikshahee@gmail.com`

**Notes:**

```
RoundPlay is a golf scorekeeping app. You enter each player's strokes on each hole; the app
allocates handicap strokes by stroke index and scores traditional golf formats.

ON GUIDELINE 5.3 — RoundPlay does not provide gambling functionality:

- It never holds, transfers, processes, or takes a cut of money.
- There is no payment functionality of any kind: no in-app purchase, no wallet, no card entry, and
  no connection to any payment processor.
- There is no wagering mechanism and no chance-based outcome. Results are determined solely by the
  golf scores the user types in.
- Where a group has agreed a stake among themselves, away from the app, RoundPlay performs
  arithmetic and displays a tally of who owes whom. Any settlement happens between the players
  outside the app, by whatever means they already use. The app states this on screen: "RoundPlay
  never holds or moves money."

HOW TO REVIEW — No account or sign-in is needed and the app works fully offline.
1. Launch the app and complete the short onboarding (a name; the handicap can be skipped).
2. Tap Start a Round, pick any course from the bundled list.
3. Choose a player count, then Next through the remaining steps.
4. Enter scores on the hole screen. The Scorecard tab shows the full card.

LOCATION — Requested once, while in use, at reduced accuracy, solely to sort the bundled course
list by distance. It is used in memory and never stored or transmitted. Declining is fully
supported; the whole course list stays searchable by name, city and state.

PRIVACY — The app has no accounts, no servers, no analytics, and no third-party SDKs. It makes no
network requests at all; the course database ships inside the binary.
```

---

## 7. Screenshots

Captured at exact required sizes from `docs/app-store/screenshots/`. Plain device captures, no
framing. Apple auto-scales the 6.9" set to smaller iPhones, so no other iPhone size is needed.

### iPhone 6.9" — 1320 × 2868 (required)

| Order | File | Shows |
|---|---|---|
| 1 | `01-scoring-group.png` | Hole 7 mid-round, four players, handicap strokes marked, scores colour-coded against par |
| 2 | `02-scoring-solo.png` | Solo mode — the one-tap grid and running score against par in the header |
| 3 | `03-games.png` | The games library with player counts and plain-English rules |
| 4 | `04-courses.png` | Course picker, sorted by distance, with the offline database |
| 5 | `05-scorecard.png` | Full landscape scorecard, 2868 × 1320 — **DECIDE**: this is the only landscape shot. It's the app's signature view, but a single landscape image in an otherwise portrait gallery looks inconsistent. Include it or drop it |

### Apple Watch — 422 × 514 (required, since the watch app ships)

Captured on Apple Watch Ultra 3, which renders at exactly the required size.

| Order | File | Shows |
|---|---|---|
| 1 | `watch/w01-hole-entry.png` | The hole screen — every player on one card, each with their own score strip, par marked on the scale |
| 2 | `watch/w02-standings.png` | Live standings against par, mid-round |

Apple requires only one, so this is sufficient. Two views are still uncaptured: the scorecard page
and the end-of-round review. The watch simulator's page swipe stops responding after a couple of
transitions, so neither could be reached — this is simulator input flakiness, not an app problem;
both work when driven by hand. Worth grabbing on a real watch if you want a fuller story, since the
review screen is where the round gets finished.

**Both files were recaptured on 2026-09-06** and show the rebuilt hole screen. Any older copy shows
UI that no longer exists.

---

## 8. Building and uploading

```bash
bundle exec fastlane beta
```

This regenerates the Xcode project, stamps a unique timestamp build number, archives, and uploads
to TestFlight. Note it uploads to **TestFlight**, not directly to App Store review — promote the
build to the App Store version in App Store Connect once it finishes processing.

Sanity-check before shipping:

```bash
xcodegen generate
xcodebuild test -project RoundPlay.xcodeproj -scheme RoundPlay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RoundPlayTests
cd Packages/RoundPlayEngine && swift test
```

Currently 19 app tests, 116 engine tests and 6 data tests, all passing.

---

## 9. After the app record exists

- [ ] **Marketing site still points at a placeholder App Store ID.** `RoundPlay/Mocks/site/public/index.html`
      carries `TODO(launch): replace id0000000000 with the real App Store ID once the app is live`,
      and both Download buttons use it. Replace and redeploy with `npx wrangler deploy` from
      `RoundPlay/Mocks/site`.
- [ ] **The site undercounts the games.** It says "Six games at launch" and lists six; the app
      ships ten (Stroke Play, Match Play, Best Ball, Skins, Nassau, Stableford, Nines, Wolf,
      Bingo Bango Bongo, Sixes). The store description above says ten, so the two will contradict
      each other until the site is updated.
- [ ] Consider whether the site's "Free while we're in beta" line should change at 1.0.

---

## 10. Deliberately not in this release

- **iPad.** The app is iPhone-only for 1.0. On a 13" iPad the layouts stretch edge to edge with
  phone-sized type and a third of the screen empty. iPad ships when it has a layout of its own.
- **Solo mode on the watch.** The watch app keeps its own quick-start flow and doesn't know about
  solo rounds.
- **Starting a round on a watch with no phone data.** The watch can start a round on its own, and
  can repeat the last one with the same group, but it can only use courses and players already
  synced from the phone — with an empty store it says "No courses yet. Add one on your phone."
