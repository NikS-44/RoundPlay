# Hole Maps and GPS Distance-to-Pin via Golfbert — Plan

**Goal:** Pick a vendor that supplies real per-hole map geometry, and scope what it takes to get
hole maps and live distance-to-pin into RoundPlay. Follows on from
`docs/plans/2026-08-29-yardage-gps-tee-mapping.md`, which scoped four related asks and
recommended a layered rollout. That doc's rollout order is now overridden by a constraint set
after it was written: **use a service that supplies hole maps and offers a free trial.** That
skips straight to what the earlier doc called "option 3", and takes manual entry and the
OSM/Overpass spike off the critical path.

**Status:** Plan only — no code. Vendor terms below were read off each vendor's own live pages
on 2026-08-30 and are quoted as *their claims*, not as verified contract terms. Nothing here
has been agreed to and no account has been registered.

## Vendor survey against the two constraints

| Vendor | Hole map geometry? | Free trial? | Verdict |
|---|---|---|---|
| **[Golfbert](https://golfbert.com)** | Yes — per-hole polygons by surface type, tee coords, flag coords, hole rotation | **Yes — "Sample Course" tier, $0, 5,000 calls/mo, self-serve** | **Recommended** |
| [Golf Intelligence](https://golfintelligence.com) | Yes — tee boxes, fairways, bunkers, penalty areas, hole outlines, green shapes, plus 3D green slope | No — course *search* is free; test credits are **$49 for 50 credits** (a full course is 3 credits) | Fails the free-trial constraint |
| [iGolf](https://igolf.com/solutions/golf-course-data/) | Yes — perimeter mapping for fairways, greens, tees, hazards, cart paths, plus elevation grids. Best coverage found: 40,000+ courses, 175+ countries | No — no pricing, no self-serve signup, "Let's Talk" enterprise form only | Fails the free-trial constraint |
| [golfapi.io](https://golfapi.io/) | Partial — "coordinates of green, tees and other points of interest"; no polygons mentioned | Unclear — a contact form mentions a free trial, nothing self-serve | Points only, and unverifiable without contacting sales |
| [GolfCourseAPI](https://golfcourseapi.com/) | **No** — scorecard/tee data only | Yes, $0 for 50 req/day | Free, but no maps — fails the maps constraint |
| [GolfLogix](https://www.golflogix.com/page/map-licensing-inquiries/) | Yes | No — licensing-inquiry form only | Fails the free-trial constraint |
| [SportsFirst](https://www.sportsfirst.net/sportsapi/golf-course-api) | n/a — reseller/integrator, not a source | n/a | Not a data source |

**Golfbert is the only vendor found that satisfies both constraints at once.** Everything below
assumes it.

> A note on one contradiction: web search summaries assert Golf Intelligence offers "50 free
> credits." Their own pricing page says $49 for 50 credits. The vendor page wins; the search
> summary appears to be wrong.

## What Golfbert actually gives you

Verified against their live public site and API surface on 2026-08-30.

**Endpoints** (`https://api.golfbert.com`):

```
GET /v1/courses                  # search; supports ?lat=&long=
GET /v1/courses/{id}
GET /v1/courses/{id}/holes
GET /v1/courses/{id}/scorecard
GET /v1/courses/{id}/teeboxes
GET /v1/holes/{id}
GET /v1/holes/{id}/polygons
GET /v1/holes/{id}/teeboxes
GET /v1/teeboxcolors
GET /v1/teeboxtypes
GET /v1/ping
```

`/v1/courses/{id}/holes` returns, per hole: `number`, `rotation` (radians — for drawing the hole
green-up), a `range` lat/long bounding box, `dimensions`, `vectors` (a `Flag` point plus one
point per tee colour: `Blue`, `White`, `Red`, …), and `flagcoords`.
`/v1/holes/{id}/polygons` returns closed lat/long rings tagged by `surfacetype` (`Green`,
and per their marketing copy fairway and hazard surfaces too).

This is precisely the shape the previous plan's `HoleGeometry` sketch was reaching for, except
it's polygons rather than single points — which is *better*, because a green polygon gives you
front/centre/back distances for free instead of only "distance to green centre."

**Coverage:** their FAQ states "over 12,500" courses, **United States only**, adding ~200/month.
RoundPlay's bundled catalog is ~15,700 US courses, so expect a meaningful fraction of courses in
the app to have no Golfbert match at all. The graceful-absence pattern the earlier plan proposed
is not optional — it's the common case.

**Health check.** Their API gateway responds (`GET /v1/courses` → `403 Missing Authentication
Token`, the correct answer to an unsigned request), and their public course browser renders real
vector hole maps (18 SVGs, 323 polygon paths on a sample course page). But the site footer reads
©2009-2024, the pricing table on `/api/plans` never finishes loading (stuck spinner), and
several doc links are `#` placeholders. **The data is live; the company's web presence looks
under-maintained.** Email `apisupport@golfbert.com` and confirm they're actively selling before
building anything on them.

### Pricing (read from their plans page)

| Tier | Price | Calls | Courses |
|---|---|---|---|
| **Sample Course** | **$0** | 5,000/mo | One sample course, for testing |
| Single Golf Course | $9/mo | 10,000/mo (+$0.005/call) | Any one course |
| All Golf Courses | $399/mo | 100,000/mo (+$0.005/call) | All courses; 5 new course mapping requests/mo |
| Static Data | $120,000 one-time (+20%/yr maintenance) | none needed | Full DB snapshot you host/embed |

**The $399/mo tier is the real number** for a consumer app whose users play arbitrary courses.
The free tier proves the integration end-to-end but cannot prove coverage — it only exposes one
sample course.

### Two license terms that shape the architecture

Both read from their API License Agreement:

1. **No bundling.** Licensees must not "download, or in any way circumvent a roundtrip to the
   API beyond what can be considered reasonable for offline use in mobile applications and only
   on a per one/two course basis and never in bulk."

   This kills the instinct — carried over from how `opengolfapi-us.json` was built — to export
   the dataset once and ship it in the app bundle. Offline caching of *the course you're
   playing* is explicitly blessed; bulk export is explicitly not. (Bulk export is what the
   $120,000 Static Data tier is for.)

2. **Return on termination.** On request the licensee must uninstall all copies "including local
   and cached data in apps and servers." Cached geometry needs to be purgeable, which it
   naturally is if it lives in its own SwiftData record.

The agreement also carries obvious boilerplate from a financial-data license template ("Named
Users", "investment research", a required "LICENSEE API LOCATION" street address for your data
centre). Worth a lawyer's eye, or at least an email asking which clauses actually apply to a
mobile app, before signing.

## The blocker nobody expects: authentication

Golfbert authenticates with **AWS Signature Version 4** — derived from an access key *and a
secret key* — plus an `x-api-key` header:

```
Authorization: AWS4-HMAC-SHA256 Credential=…/…/us-east-1/execute-api/aws4_request,
SignedHeaders=content-type;host;x-amz-date;x-api-key, Signature=…
```

**The secret key cannot ship inside the app.** Anything in an iOS binary is extractable, and a
leaked key on the $399/mo tier is somebody else's bill. So the app cannot call Golfbert directly
— it needs a proxy that holds the credentials and signs on the app's behalf.

That is less of an imposition than it sounds, because **RoundPlay already deploys a Cloudflare
Worker** — `blue-wave-596a`, the assets-only Worker serving roundplay.app
(`RoundPlay/Mocks/site/wrangler.jsonc`). A second Worker alongside it, holding the Golfbert keys
as Wrangler secrets and signing with `aws4fetch`, is a well-trodden path and buys two more
things:

- **Call-budget protection.** Loading one course costs ~21 calls (1 holes + 18 polygons + 1
  teeboxes + 1 scorecard). At 5,000 free calls that's ~238 course loads/month — fine for
  development. Cache per course in the Worker (Cache API or KV) and the second user to play a
  course costs zero upstream calls.
- **Vendor portability.** If Golfbert goes dark — and the ©2024 footer is a real signal — the
  app talks to *your* endpoint, and swapping the upstream is a Worker deploy, not an app
  release.

It also introduces the thing the OpenGolf plan deliberately avoided: a network dependency and a
service you now operate. That trade is unavoidable given the constraint; it's worth naming
rather than discovering later.

## What changes in the app

### Location services — yes, and the existing one won't do

`RoundPlay/Services/NearbyCourseLocator.swift` already handles CoreLocation, and
`NSLocationWhenInUseUsageDescription` ("Find golf courses near you.") is already in
`project.yml`. But it is deliberately built for the *opposite* of this feature and none of it
carries over:

| Today (`NearbyCourseLocator`) | Needed for distance-to-pin |
|---|---|
| `kCLLocationAccuracyReduced` — city-block precision ([:27](RoundPlay/Services/NearbyCourseLocator.swift:27)) | `kCLLocationAccuracyBest`; reduced accuracy is off by more than the shot you're measuring |
| One-shot `requestLocation()` ([:30](RoundPlay/Services/NearbyCourseLocator.swift:30)) | `startUpdatingLocation()` while the hole screen is visible, stopped when it isn't |
| Precise Location not required | **Must request it.** A user on system-level Reduced Accuracy silently gets useless fixes unless you call `requestTemporaryFullAccuracyAuthorization(withPurposeKey:)` and add `NSLocationTemporaryUsageDescriptionDictionary` to Info.plist — the single easiest thing to miss here |
| Usage string is about finding courses | Must be rewritten to cover live measurement, or App Review will flag the mismatch |

Build a separate `HoleDistanceLocator` rather than widening `NearbyCourseLocator` — the two want
opposite accuracy, lifetime, and battery postures, and the honest permission story for course
search stays honest.

**Foreground-only for v1.** Keeping `WhenInUse` and running the updater only while the hole
screen is on avoids `allowsBackgroundLocationUpdates`, the Background Modes entitlement, and the
extra App Review scrutiny that comes with it. Continuous best-accuracy GPS across a 4½-hour
round is a real battery cost; scoping it to the visible hole screen is both the cheap fix and
the honest one.

**Accuracy expectation:** consumer phone GPS lands around 3–5 m under open sky, so roughly ±5
yards. That is what every golf GPS app is actually delivering, and it's fine for "142 to
centre." Distance itself is `CLLocation.distance(from:)` (WGS-84 ellipsoid, more accurate than
the haversine the earlier plan assumed) × 1.09361 for yards. Front/centre/back come from the
green polygon: centroid for centre, and the nearest/farthest vertices along the player's bearing
for front/back.

### Data model

The earlier plan's sketch needs widening from points to polygons:

```swift
struct HoleGeometry: Sendable {
    let holeNumber: Int
    let rotation: Double                     // radians; draw the hole green-up
    let bounds: MKMapRect                    // from Golfbert's `range`
    let flag: CLLocationCoordinate2D
    let teeBoxes: [TeeBox]                   // colour/name + coordinate
    let surfaces: [HoleSurface]              // .green/.fairway/.bunker/.water + ring
}
```

Persist as **one encoded blob per course** in a new `CourseGeometryRecord`, not as a modelled
object graph — a course is 18 holes × ~5 surfaces × 30–300 points each, roughly 100–500 KB of
coordinates, and SwiftData has no reason to see individual vertices. `CourseRecord` gains a
`golfbertCourseID: String?`; a course with no geometry simply has no record, so nothing about
existing courses, rounds, or the 116 engine tests changes.

Note the sync surface: `SyncSnapshots`/`SyncMerger` carry `CourseRecord` to the watch. Geometry
blobs must **not** ride along wholesale over WatchConnectivity. If the watch gets distances,
send it 18 green-centre coordinates (a few hundred bytes), not polygons.

### Course matching

RoundPlay's courses key off `openGolfID` from the bundled catalog; Golfbert has its own IDs.
Bridging them is its own small subsystem: search `/v1/courses?lat=&long=` using the catalog's
course coordinate, fuzzy-match on name, store the result on `CourseRecord`. Given 12,500
Golfbert courses against ~15,700 catalog entries, plan for both misses and ambiguous matches —
a "this doesn't look right, pick the correct course" affordance is likely needed rather than
silent auto-matching.

### Rendering

MapKit, no additional vendor. SwiftUI `Map` with `MapPolygon` overlays on
`.imagery`/`.hybrid` style gives satellite imagery free from Apple under the Golfbert polygons.
Golfbert's own FAQ suggests SVG over satellite for performance; native `MapPolygon` over Apple
imagery is the idiomatic iOS answer and worth measuring before optimising away. `rotation` +
`range` frame each hole tee-down/green-up.

### UI placement

- **Distance readout:** into `HoleHeader`
  ([HoleScreenView.swift:531](RoundPlay/Features/Scoring/HoleScreenView.swift:531)), which
  currently holds Par left and Handicap right with the middle occupied by the leader/Wolf line.
  Three distances (F/C/B) plus the existing four elements is a crowded header — this needs a
  design pass, not just an insertion.
- **Hole map:** a separate screen pushed from the hole screen, not embedded — a map inside the
  scoring flow competes with score entry for the same thumb.
- **Absence:** no permission, no fix, no Golfbert match, or no geometry all render as *nothing*,
  never as an error or an empty state. On most courses, most of the time, that's what users see.

## Rollout

| # | Phase | Cost | Rough size |
|---|---|---|---|
| 0 | **Email Golfbert.** Confirm they're actively selling, that $399/mo All Courses is current, and which license clauses apply to a mobile app | free | an email |
| 0b | **Coverage check by hand.** Look up the courses you actually play in golfbert.com's public course browser. No API key needed, and it answers the one question the free tier can't | free | an hour |
| 1 | **Spike on the free tier.** Register, pull the sample course, render one hole's polygons in a scratch SwiftUI `Map`. Validates auth, data shape, and rendering in one go | free | ½–1 day |
| 2 | **Cloudflare Worker proxy.** SigV4 signing via `aws4fetch`, keys as Wrangler secrets, per-course caching | free | ~1 day |
| 3 | **Matching + fetch + persist.** `golfbertCourseID` on `CourseRecord`, `CourseGeometryRecord`, catalog→Golfbert matching | free tier covers dev | ~2–3 days |
| 4 | **GPS distance-to-pin.** `HoleDistanceLocator`, full-accuracy authorization, Info.plist strings, `HoleHeader` design pass | free tier covers dev | ~2 days |
| 5 | **Hole map screen.** MapKit overlays, rotation, framing | free tier covers dev | ~3–4 days |
| 6 | **Go paid.** Only at this point does the $399/mo (or $9/mo single-course) decision have to be made | $9–$399/mo | — |
| 7 | **Watch distances.** Green-centre coords over WatchConnectivity, watchOS CoreLocation + its own usage string | | ~2 days |

Phases 1–5 are all buildable on the $0 tier. **The money decision is deferrable to phase 6** —
by which point the feature works and you know whether the courses you care about are covered.

## Open questions

- **Is Golfbert still a going concern?** Data live, API live, website stale. Phase 0 exists
  entirely to answer this before any code is written.
- **Does $399/mo survive contact with the business model?** A subscription golf app can carry
  it; a free one can't. Worth deciding before phase 5, not after.
- **What's the fallback if a course has no Golfbert match?** Manual per-tee yardage entry —
  option 1 from the earlier plan — is still the honest answer for uncovered courses, and it
  doesn't stop being useful just because a vendor is now in the picture.
- **Attribution.** Golfbert's agreement forbids removing their proprietary notices; whether that
  implies visible in-app attribution needs asking, not assuming.
- Course rating/slope remains out of scope, as the earlier plan concluded. Golfbert's
  `/teeboxes` endpoints may supply it as a side effect; that doesn't make it this pass's job.
