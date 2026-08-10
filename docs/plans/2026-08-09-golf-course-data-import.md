# Local Golf Course Database — Plan

**Goal:** Bundle [opengolfapi/data](https://github.com/opengolfapi/data) (16,908 US courses, ODbL)
directly in the app as an offline, local database. Finding your course becomes the happy path —
search by name or "nearest me," favorite the ones you play — and the existing manual 18-hole
entry (`CourseEntryView`) becomes the fallback for the course nobody's indexed yet, not the
default.

**Status:** Superseded the earlier third-party-API version of this plan (below) after checking the
actual data. No live API, no network dependency, no vendor ToS risk — everything ships in the app
bundle and runs fully offline, which is also just a better fit for "first tee, spotty signal."

## What's actually in the data (checked against the real CSV, not the README's summary)

I pulled `opengolfapi-us.csv` directly and checked it against what `Course.validated` requires
(exactly 18 holes, sequential numbers, stroke indexes forming a clean 1–18 permutation, par 3–6)
before assuming the README's "90% hole-by-hole par + handicap index coverage" claim would translate
into 90% of courses being immediately playable:

- **15,667 rows total** in this snapshot (README says 16,908 — the file updates independently of
  the README, not a discrepancy worth worrying about).
- **Only 22 rows have a complete, engine-valid 18-hole scorecard** (all 18 `hole_N_par` and all 18
  `hole_N_hcp` columns populated, stroke indexes forming a clean 1–18 permutation). That's 0.14% of
  the dataset, not 90%.
- The `holes` column is **not** a reliable hole count — it turns out to equal the number of
  populated `hole_N_par` columns for that row, not the course's actual hole count. A normal
  18-hole course with `par` (total) `= 72` frequently has `holes = 14` in this column because only
  14 of its 18 individual hole pars were captured. Don't trust `holes`; trust `par` (total) as the
  "this is probably a real 18-hole course" signal instead, and treat the per-hole arrays as
  **partial** regardless of what `holes` says.
- Name, coordinates, city/state, type, phone, website, address are all high-coverage (matches the
  README) and don't have this problem — it's specifically the hole-by-hole par/stroke-index arrays
  that are sparse.

**Consequence for the design:** this data source is excellent for *finding and identifying* a
course — name, location, "nearest me," favoriting — and it's realistic for most US courses. It is
**not** reliable enough to silently hand the engine a fabricated stroke-index sequence. The design
below treats hole-by-hole data as best-effort pre-fill into the existing manual-entry screen, not
as a green light to skip validation.

## Storage: bundled file, not a network call

- Ship `opengolfapi-us.csv` (4.8 MB uncompressed, 1.8 MB gzipped) as an app bundle resource.
  Gzip in the bundle, decompress once into memory on first use (`Compression` framework, no new
  dependency) — trades a trivial one-time CPU cost for keeping ~3 MB out of the shipped IPA.
- Parse into an in-memory `[OpenGolfCourse]` at first access (a few thousand structs — trivial
  for a phone, no need for SQLite/Core Data/GRDB for a dataset this size). Cache the parsed array
  for the process lifetime.
- **No new SPM dependency required.** A small hand-rolled CSV parser is enough — the only quoting
  wrinkle is fields like `architect` containing commas inside quotes (`"Tim Nugent, Dick Nugent"`),
  which needs a real quote-aware parser, not `split(",")`.
- Favorites and "courses I've actually played here" state are local `SwiftData` records (a
  lightweight `FavoriteCourseRecord` keyed by the OpenGolf `id`), same store as everything else in
  the app. Nothing here talks to the network or a backend, matching "not in the cloud if possible."

## Data model

```swift
/// One row from the bundled OpenGolf dataset. Not a SwiftData @Model — parsed once into memory,
/// not persisted; only what the user *does* with a course (favorite it, play it) becomes a record.
struct OpenGolfCourse: Identifiable, Sendable {
    let id: String                  // OpenGolf UUID string
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String
    let state: String?
    let city: String?
    let type: String?               // public / private / municipal / resort / military / par3
    let totalPar: Int?
    let phone: String?
    let website: String?
    let yearBuilt: Int?
    let address: String?
    let postalCode: String?
    let architect: String?
    /// Sparse: index 0 is hole 1. `nil` where the source has no value for that hole.
    let holePars: [Int?]            // count 18, may have holes
    let holeHandicaps: [Int?]       // count 18, may have holes

    /// True only when every hole has both par and stroke index and the handicaps form a clean
    /// 1–18 permutation — i.e. this can go straight through `Course.validated` with zero edits.
    var isEngineReady: Bool { ... }
}
```

- Keep the metadata fields (`type`, `phone`, `website`, `yearBuilt`, `architect`, `address`) even
  though nothing reads them yet — matches "keep as much metadata as reasonable" and costs nothing
  since it's already in the source file.
- No mapping/geometry beyond the point coordinate — explicitly out of scope per the ask.

```swift
@Model
final class FavoriteCourseRecord {
    var openGolfID: String = ""
    var name: String = ""           // denormalized so favorites render without re-parsing the CSV
    var city: String?
    var state: String?
    var favoritedAt: Date = Date()
}
```

## UX

**`CourseListView` becomes "Find a Course"**, replacing today's flat "recent courses + add a
course" list:

1. **Nearest** — top section, populated via `CoreLocation` (one-shot location request, no
   background tracking) sorted by haversine distance. Requires a location permission prompt with a
   plain-English reason ("Find your course by GPS"); if denied or unavailable, this section just
   doesn't render — never a dead/broken state.
2. **Favorites** — courses the user has starred, via `FavoriteCourseRecord`. Empty until someone
   favorites something.
3. **Search** — text field filtering the in-memory `[OpenGolfCourse]` by name (and city/state, so
   "Springfield" surfaces courses in the town, not just courses named "Springfield").
4. **Recently played** — existing `CourseRecord` history stays, since a course played once should
   stay one tap away regardless of where it came from.
5. **"Can't find your course? Add it manually"** — permanent fallback link at the bottom to the
   existing `CourseEntryView`, unchanged. This is now explicitly the *fallback* path, not the
   default one, per the ask.

**Selecting an `OpenGolfCourse`:**
- If `isEngineReady` (has that clean 18-hole scorecard) — pre-fill `CourseEntryModel` completely
  and show the existing `CourseEntryView` steppers already populated, for a quick glance-and-save
  instead of a blank form. Still goes through the same `Course.validated` gate as manual entry;
  nothing bypasses it.
- If not engine-ready (the common case) — pre-fill whatever holes *are* known (name, and each
  hole's par/stroke-index where present) into the same `CourseEntryModel`/`CourseEntryView`, and
  leave the rest at today's defaults for the user to fill in on the steppers. This turns "type 18
  numbers" into "confirm the ones we already know, fill in the few we don't," without ever
  pretending we have data we don't.
- Either way, saving creates a normal `CourseRecord` exactly as manual entry does today — store the
  OpenGolf `id` on it (new optional field) so re-selecting the same course later can be recognized
  as "already added" rather than creating a duplicate.

**Favoriting** — a star affordance on each course row in Nearest/Search results, writable without
first creating a `CourseRecord` (you can favorite a course you haven't played yet, e.g. planning a
trip).

## License / attribution

ODbL requires `source=OpenGolf` attribution in derived work. Add a small "Course data from
OpenGolf" credit (with the ODbL link) on the Find a Course screen or in Settings — cheap to add,
required by the license, not optional.

## Open questions

1. **Update cadence.** The bundled CSV is a point-in-time snapshot; it goes stale the moment
   OpenGolf's community edits it. Fine for a proof of concept; a real version would need either an
   app-update-triggered refresh or a background download of a newer snapshot — deliberately
   deferred, since "not in the cloud if possible" and "proof of concept" both point at bundling for
   now.
2. **International data.** Only the US export currently exists on that repo (16.9k of the
   database's reported 32k+ courses worldwide). Fine to ship US-only first; revisit if RoundPlay's
   users aren't all US-based.
3. **Duplicate/near-duplicate detection.** Community-sourced OSM data has the occasional duplicate
   course entry under slightly different names — not solved here; worth a pass if it turns out to
   be common enough to annoy users in search results.

## Suggested next step

This plan is scoped tight enough to implement directly — no vendor spike or coverage check needed,
since the coverage numbers above already come from the real file. Next: bundle the CSV, write the
parser + `OpenGolfCourse` model, and build the Find a Course screen per the UX section above.
