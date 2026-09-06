# Disc Golf in RoundPlay: feasibility and data-source research

**Decision memo · September 5, 2026 · U.S.-first assumption**

## Executive answer

Yes—RoundPlay can support disc golf, and the existing score-entry experience is a useful foundation. The first release should be framed as **disc-golf scorekeeping plus a subset of compatible games**, not as a cosmetic rename of golf mode.

The main blocker is not scoring. The PDGA defines a hole score as total throws including penalty throws, and a round as the sum of hole scores, so RoundPlay's basic integer-per-player-per-hole event model fits directly ([PDGA Rule 808](https://www.pdga.com/rules/official-rules-disc-golf/808)). The blockers are course shape and handicapping: RoundPlay currently requires exactly 18 holes, par 3–6, and a unique 1–18 stroke-index sequence; disc golf commonly has nine-hole and other layouts, multiple tees/baskets, and no golf-style stroke-index field.

There is also no mature, comprehensive, downloadable disc-golf equivalent of the OpenGolf file. The best practical source today is the new **DiscGolfAPI**, supplemented by manual layout entry. It has useful licensing and structured records, but only 4,065 U.S. courses and generally layout-summary—not hole-by-hole—data. Before commercial release, RoundPlay should get written confirmation of permitted app caching/bundling because the site's public licence says the API/JSON may be used freely in apps while its terms invite contact for commercial use and prohibit full-dataset republication as a competing service.

**Recommendation:** build a small sport/layout abstraction, ship a disc-golf MVP with stroke play, match play, skins, and straight-up variants of several existing games, use DiscGolfAPI for course discovery with manual completion of scorecards, and treat a fully offline nationwide catalog as a later data-partnership or community-data project.

## What course data is actually available

| Source | Coverage and fields | Legal/operational fit | Verdict |
|---|---|---|---|
| **DiscGolfAPI** | Snapshot dated Aug. 10, 2026: 6,582 courses in 26 countries, including 4,065 U.S.; 5,892 have a hole count. Records include coordinates, status/access, confidence, and a primary layout summary with hole count, total par, and length when known. Public docs do not expose per-hole pars/tees/baskets ([coverage](https://discgolfapi.com/coverage/), [schema/docs](https://discgolfapi.com/docs/)). | No key; read-only; cache encouraged. Visible attribution required. Licence permits apps and public JSON, but terms allow endpoint changes/removal, prohibit full-dataset republication as a competing service, and say to contact them for commercial use ([licence](https://discgolfapi.com/licence/), [terms](https://discgolfapi.com/terms/)). It is a young beta: public coverage grew from 560 courses in April to 6,582 in August 2026 ([changelog](https://discgolfapi.com/changelog/)). | **Best MVP discovery source**, with manual scorecard completion and a commercial-use email first. Do not make it RoundPlay's only path. |
| **OpenStreetMap / Overpass** | Open and extractable. The established model uses `leisure=disc_golf_course`; hole ways can carry number (`ref`) and par. But current mapping is sparse: roughly 2,700 course objects and about 10,000 holes globally, versus 17,287 real-world courses reported by UDisc ([OSM tagging](https://wiki.openstreetmap.org/wiki/Disc_golf), [hole schema](https://wiki.openstreetmap.org/wiki/Tag:disc_golf=hole), [UDisc 2026 total](https://udisc.com/disc-golf-growth-report/2026)). | ODbL permits copying and adaptation with attribution and requires distributed derivative databases to remain under the same licence ([OSM copyright/licence](https://www.openstreetmap.org/copyright)). RoundPlay already handles this licence family through OpenGolf. Producing a bundled extract is technically straightforward. | **Good legal fallback and future enrichment source; inadequate as the primary catalog today.** |
| **UDisc** | The strongest directory by a wide margin: 17,287 active/publicly available courses worldwide at end-2025, with the U.S. just under 65% of the total—roughly 11,000 by inference ([course-count methodology](https://udisc.com/blog/post/how-many-disc-golf-courses-in-the-world), [country totals](https://udisc.com/blog/post/every-country-with-a-disc-golf-course)). | No documented public developer API or bulk/open licence was found. Public pages and support documentation are user-facing directory tools, not permission to scrape and redistribute the database. | **Do not scrape.** Explore a licensing/partner conversation only if comprehensive coverage becomes strategically important. |
| **PDGA directory** | Authoritative association directory with user-account-based add/edit workflow ([directory help](https://www.pdga.com/help/course-directory)). | No current public bulk-download licence or open developer API was found. The site content is copyrighted. | Useful for manual verification; **not a shippable dataset without an agreement**. |

No candidate supplies what RoundPlay ideally wants—broad U.S. coverage plus complete hole-by-hole pars, layouts, and stable IDs in a downloadable, commercially clear file. This means course selection should identify the venue/layout and reduce typing, while a confirmation screen completes missing hole data.

## Scoring and game compatibility

The user's intuition is right for the core loop: a throw is a stroke-like count, lower total wins, and relative-to-par presentation works. PDGA match play also matches RoundPlay's hole-won/halved model ([PDGA Match Play](https://www.pdga.com/rules/official-rules-disc-golf/appendix-a)). Penalties need no separate engine concept for casual play if the entered total already includes them, though a later `+ penalty` affordance would improve auditability.

| Existing RoundPlay mode | Disc-golf fit | What to change |
|---|---|---|
| Stroke Play | **Direct fit** | Rename UI language from strokes to throws where appropriate; allow penalty annotation. |
| Match Play | **Direct fit** | Default to gross/straight-up. PDGA explicitly supports holes won and halved. |
| Skins | **Direct casual fit** | Default gross scores; retain carryover configuration. |
| Nines | **Likely direct fit** | It compares per-hole scores; validate naming with disc golfers in beta. |
| Wolf | **Mechanically compatible** | Gross scores work, but validate that users recognize/want the game rather than assuming golf vocabulary transfers. |
| Stableford | **Mechanically compatible, culturally nonstandard** | Offer only as an optional game; use gross relative-to-par unless RoundPlay introduces a disc-golf handicap model. |
| Nassau | **Only for 18-hole layouts** | It assumes front 9/back 9/total. Hide it on non-18 layouts, as the current builder already does for partial golf rounds. |
| Sixes | **Only for 18 holes / four players** | Hide for other layout sizes or later generalize partnership blocks. |
| Bingo Bango Bongo | **Needs a rules definition** | “First on the green” is not naturally defined in disc golf. A ten-metre putting-circle interpretation is possible but requires extra event input and clear house rules. |
| Best Ball | **Name/expectation trap** | RoundPlay's implementation is PDGA **Best Score** (each player completes the hole and the team uses its lower score), not the far more popular disc-golf **Best Throw/Best Shot** scramble where partners repeatedly choose a lie. The PDGA distinguishes these formats ([Doubles Appendix](https://www.pdga.com/rules/official-rules-disc-golf/appendix-b)); rename the existing option to Best Score in disc mode and add Best Shot only with a team-level scoring workflow. |

### Handicaps are the largest scoring difference

RoundPlay allocates a golf course handicap across holes using a 1–18 stroke index. Disc-golf course sources do not provide that field, and PDGA player ratings are performance ratings, not a plug-compatible course handicap. The MVP should therefore offer **Straight up** by default and hide the current handicap/strokes onboarding and setup steps for disc golfers. A later disc-golf handicap feature should be designed deliberately from round history or a documented league method; it should not reuse a PDGA rating as if it were a golf handicap.

## Fit with the current codebase

The catalog/search UX can be reused almost directly: RoundPlay already decodes a bundled reference catalog once, searches it in memory, and sorts by distance. The new source should sit behind a sport-neutral catalog protocol rather than adding disc fields to `OpenGolfCourse`.

The required engine change is broader but contained:

1. Add `Sport` (`golf`, `discGolf`) to player preferences, course/layout records, and rounds. Store it on every round so later onboarding changes cannot reinterpret history.
2. Change `Course` to a venue/layout shape with a variable sequential hole array. Make `strokeIndex` optional or move golf handicapping into golf-specific hole metadata. Keep golf validation strict while disc validation accepts at least common 6/9/12/18/21/24/27 layouts—and preferably any sensible positive count.
3. Replace `RoundSegment.front/back/total` as the universal representation with an explicit ordered hole selection or range. Derive front/back only for 18-hole layouts.
4. Add `CourseLayout` identity. Disc courses can have short/long tees and alternate baskets; treating only the venue as a course will corrupt par/history when layouts change.
5. Filter games by sport and layout capabilities (`hasStrokeIndexes`, `holeCount == 18`, `supportsPuttingCircleEvents`) rather than player count alone.
6. Generalize score-entry copy (`throws` in disc mode) but preserve the existing integer score event. Add optional penalty-throw notes later, not as an MVP blocker.

The existing hard constraints are visible in `Course.validated`: exactly 18 sequential holes, par 3–6, and a complete 1–18 stroke index. The onboarding flow also proceeds immediately from name to a golf handicap and stores only `OpenGolfCourse` favorites. Those are the two first refactoring seams. The new catalog can preserve the existing offline/manual fallback philosophy, but a DiscGolfAPI-backed version needs cached responses and a calm offline state.

## Suggested product sequence

### Phase 0 — one-week data and UX spike

- Ask DiscGolfAPI for written confirmation covering a paid App Store app, on-device caching, attribution placement, request volume, and whether a versioned full snapshot may be bundled.
- Pull the U.S. API snapshot and measure: geocoded percentage, hole-count percentage, primary-layout par percentage, duplicates, and coverage within RoundPlay's likely launch states. The public coverage page does not answer all of these.
- Prototype `Sport` plus variable hole counts in the engine and run the full existing test suite to expose hidden 18-hole assumptions.

### Phase 1 — credible MVP

- Onboarding asks **What do you play? Golf / Disc golf / Both** before handicap. Golf/both users see the golf handicap question; disc-only users do not.
- Disc course finder uses DiscGolfAPI live data with an on-device cache and permanent **Add a course/layout manually** fallback.
- Selecting a result opens layout confirmation: layout name, hole count, and per-hole par. Provide an explicit **Set all to par 3** action, never a silent fabricated scorecard.
- Enable Stroke Play, Match Play, Skins, Nines, and optionally Wolf, all straight-up. Rename Best Ball to Best Score if exposed. Hide incompatible games by capability.
- Preserve nearby search, favorites, Apple Watch entry, summaries, and sharing after making their loops hole-count-driven.

### Phase 2 — disc-native depth

- Add Best Shot doubles with one team score per hole.
- Add alternate tees/baskets, course-layout updates, penalty annotations, and course correction/reporting.
- Research a transparent recreational handicap separately, using actual RoundPlay round history.
- If demand is proven, pursue UDisc/PDGA licensing or build a community-maintained ODbL catalog with import tooling and periodic snapshots.

## Go/no-go call

**Go for an MVP.** The core scorekeeping/event model and much of the UI are reusable, and disc golf is large enough to justify the option: UDisc reports 17,287 courses worldwide, 21.2 million recorded rounds in 2025, and 1,100+ new courses annually for six years ([2026 Growth Report](https://udisc.com/disc-golf-growth-report/2026)).

Do not make “complete automatic course scorecards” an MVP promise. A defensible launch promise is: **find many nearby disc-golf courses, confirm or quickly fill the layout, then keep group scores and compatible side games with the same RoundPlay flow.** The decision gate after the spike is whether DiscGolfAPI coverage is good enough in target states and whether its commercial/cache terms are confirmed. If either fails, launch with manual layouts plus OSM-assisted discovery rather than scraping proprietary directories.

## Limitations and confidence

- Research reflects sources available September 5, 2026 and assumes a U.S.-first commercial iOS release.
- Confidence is **high** on scoring/rules and RoundPlay code constraints; **medium** on course-source recommendations because DiscGolfAPI is new and changing quickly; **low** that any open source currently provides complete hole-level coverage.
- DiscGolfAPI's published licence language is not a standard CC/ODbL grant on its licence page despite API responses reportedly identifying CC BY 4.0. Because its terms also request contact for commercial use, written clarification is prudent before implementation.
- No undocumented endpoints or proprietary sites were scraped, and source counts were not treated as proof of hole-level completeness.
