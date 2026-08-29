# Yardage, GPS Distances, Tee Boxes, and Course Mapping — Plan

**Goal:** Scope the next steps for four related asks — yardage per hole, live GPS
distance-to-pin during a round, tee-box support, and a hole/course map view — and figure out
what data source(s) they actually need, since the bundled OpenGolf dataset RoundPlay already
ships (`docs/plans/2026-08-09-golf-course-data-import.md`) has none of this.

**Status:** Plan only — no code. This is scoping and a recommended rollout order, to be turned
into real specs/plans per phase once a direction is picked.

## What we actually have today (checked the source, not assumptions)

- **Engine (`Course.swift`):** `Hole` is `number`, `par`, `strokeIndex`. No yardage, no
  coordinates, no tee concept at all. `Course.validated` only enforces 18 holes, a 1–18
  stroke-index permutation, and par 3–6.
- **Persisted (`CourseRecord`, SwiftData):** `name`, `pars`, `strokeIndexes`, `openGolfID`.
  That's it — not even the single course-level lat/long survives from catalog selection into
  a saved course. Once a round is created, there is *no* location data attached to it at all.
- **Catalog (`OpenGolfCourse`, the bundled opengolfapi rows):** one `latitude`/`longitude` pair
  for the whole course (clubhouse-ish, not per-hole), plus `holePars`/`holeHandicaps` — the
  same sparse arrays the import plan already flagged as ~0.14% complete. No yardage field, no
  tee data, no per-hole geometry, at any completeness. This isn't a gap in how we read the
  data — the source file itself doesn't carry it.
- **Handicap engine (`HandicapAllocation`, etc.):** no course rating or slope anywhere in the
  codebase. Worth flagging because course rating/slope is normally tee-specific too, and it's
  the kind of thing people expect to arrive bundled with "add tee boxes" — it's a related but
  separate ask, out of scope for this pass unless folded in deliberately.

**Bottom line:** this isn't "extend the existing pipeline" — it's three separate gaps (yardage,
finer-than-one-point-per-course geometry, and the tee-box concept itself), and the data source
already in the app supplies none of them.

## Data source options

1. **Manual entry, same spirit as today's `CourseEntryView` fallback.** User types yardage per
   hole per tee when setting up a course. Zero licensing risk, zero new dependency, works for
   every course including ones nobody's mapped — but it's 18 × (number of tees) numbers, a real
   step up from today's 36-number worst case. This is the one piece buildable immediately with
   no spike.
2. **OpenStreetMap golf tagging via Overpass API** (`golf=tee`/`golf=green`/`golf=fairway` ways
   and nodes). Same license family (ODbL) already accepted for the opengolfapi bundle, and it's
   the only free source with real per-hole *geometry* (tee and green locations/polygons) for
   courses that have been mapped. Two real unknowns before committing: coverage varies course
   by course depending on volunteer mapping effort (unlike opengolfapi's uniform-but-shallow
   coverage, this is patchy-but-deep), and it has no yardage or tee-box metadata at all — it
   would need to be paired with option 1 or 3, not replace them. Needs a coverage spike against
   a sample of real courses before deciding it's worth an Overpass-to-bundle export pipeline
   (mirroring how the opengolfapi CSV/JSON was built).
3. **A commercial golf-course-data API** with real per-tee yardage and course rating/slope.
   Realistically the only source for *authoritative* multi-tee yardage, but it reopens a
   decision the OpenGolf plan explicitly closed: "no live API, no network dependency, no vendor
   ToS risk, everything ships offline." Committing here means re-litigating that call —
   licensing terms, per-course pricing, and rate limits all need a dedicated spike, and I'm not
   treating any specific vendor's current terms as verified without doing that spike first.

**Recommendation:** layer it, cheapest and lowest-risk first.
- Ship manual tee/yardage entry (option 1) first — no new source, no spike, immediate value for
  anyone willing to type their scorecard's yardage in once.
- Spike Overpass coverage (option 2) next, specifically for geometry (tee/green points), since
  it stays inside the existing offline-bundle, no-vendor-lock posture.
- Treat a paid API (option 3) as a later upgrade, only if 1+2 together prove insufficient for
  what users actually ask for.

**GPS distance-to-pin is a separate feature on top of whichever source wins.** It needs a
*live* location fix during play (`CoreLocation`, foreground-only, same permission pattern the
Nearest-courses search already uses) and a per-hole green coordinate to measure against —
it doesn't care which option above supplied that coordinate. It can't ship before some source
supplies per-hole geometry, but once one does, the distance math itself is a small haversine
calculation, not a new subsystem.

## Proposed data model (sketch, not final)

Extending `Hole` directly would touch a struct used throughout scoring and all 116 engine
tests for data that scoring never needs — recommend keeping this as a separate, optional
structure instead, so `Course.validated` and every existing test stay untouched:

```swift
// New, engine-adjacent but not part of scoring — presentation/mapping data only.
struct TeeSet: Identifiable, Sendable {
    let id: UUID
    let name: String            // "Blue", "Championship", etc.
    let rating: Double?
    let slope: Int?
}

struct HoleGeometry: Sendable {
    let holeNumber: Int
    let yardageByTee: [UUID: Int]     // TeeSet.id -> yards
    let teeCoordinate: CLLocationCoordinate2D?
    let greenCoordinate: CLLocationCoordinate2D?   // center is enough for v1; front/back later
}
```

Persisted as a new `CourseGeometryRecord` (SwiftData), optionally linked from `CourseRecord`,
so a course with no geometry yet (the common case, at least at first) simply has no record —
nothing about existing courses or rounds needs to change.

## UX sketch

- **Tee selection:** a picker ("Playing from: Blue") appears in round setup only when a course
  actually has `TeeSet` data — invisible for every course that doesn't, so this never looks
  like a missing feature on courses without it.
- **Yardage display:** a yardage readout next to Par on the hole-entry header (`HoleHeader`,
  already reworked for Par prominence in this session's item 2), shown only when known for the
  selected tee.
- **GPS distance-to-pin:** a small live readout ("142 yds to green") on the hole-entry screen.
  Same graceful-absence pattern as Nearest-courses: no permission, no fix, or no green
  coordinate all just mean the readout doesn't render — never a broken-looking state.
- **Hole/course mapping:** a MapKit view per hole showing tee/green (and fairway outline, if
  OSM coverage includes it). This is the most speculative and most expensive piece of the four
  — sequence it last.

## Rollout order

1. Manual per-tee yardage entry (no new source, no spike).
2. Overpass/OSM coverage spike, then a geometry import pipeline if coverage justifies it.
3. GPS distance-to-pin, once some source supplies a green coordinate.
4. Hole/course map view.
5. Paid vendor API — only if the above prove insufficient.

## Open questions

- Does course rating/slope belong in this pass, given tee boxes are the natural place users
  would expect to see it, or is it a genuinely separate handicap-engine change? Leaning
  separate — `HandicapAllocation` doesn't use it today and folding it in here risks scope
  creep across two different subsystems.
- What attribution/licensing does bundling OSM golf data require beyond what the existing
  opengolfapi ODbL notice already covers? Needs checking before pipeline work starts, not
  after.
- How should the UI communicate "this course has none of this yet" without looking broken,
  given that — realistically — most courses won't have tee/geometry data for a long while
  after this ships? The graceful-absence pattern above is the starting assumption, not a
  settled answer.
