# RoundPlay Phase 1a — Scoring Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the six scoring engines — Skins, Nassau, Stableford, Nines, Wolf, Bingo Bango Bongo — as pure functions over an append-only event log, with a JSON fixture suite that the Phase 4 TypeScript port will be verified against.

**Architecture:** Everything lives in `Packages/RoundPlayEngine`, a Swift package with `Foundation` as its only dependency. An append-only `[ScoreEvent]` folds into a `RoundState` (current gross/net per hole per player); each engine is a static function from `RoundState` to `Settlement`. No engine reads a database, a clock, or a network — given the same log, each returns the same money, forever.

**Tech Stack:** Swift 6.2, swift-testing (`import Testing`), `Decimal` for money.

## Execution Mode

Run this plan's tasks continuously, start to finish, without pausing for step-by-step
approval or asking "should I proceed?" between tasks. Run each verification command as
specified and move on when it passes. **Only stop and ask the user when a decision is
genuinely controversial or ambiguous** — a product/scope/rules judgment call this plan
doesn't already resolve, not an implementation detail. When you do have a reasonable
recommendation, state it briefly and keep going rather than blocking on confirmation.
This applies to every plan in this project, in this session and any future one.

## Global Constraints

- Swift tools version **6.2**. All public types are `Sendable`, `Equatable`, and `Codable` unless stated otherwise.
- **The package must never import SwiftUI, UIKit, SwiftData, Combine, or any networking module.** `Foundation` only. A CI grep enforces this in Task 11.
- **Do not run `xcodebuild`.** Verification is `cd Packages/RoundPlayEngine && swift test`.
- **Money is `Decimal`, never `Double`.** Floating-point money is a correctness bug in an app whose whole job is settling bets.
- **Every settlement must be zero-sum**: the money awarded across all players sums to exactly `0`. Every game gets this test.
- Engines are **pure**: no `Date()`, no `UUID()` generated inside a settle function, no randomness. Determinism is the property the whole design rests on.
- Rule variants are **configuration, not code**. Point values, press rules, and carryover behavior are config fields with documented defaults — never hardcoded constants.
- Source of truth for rules: `docs/specs/2026-08-08-roundplay-design.md` §5.2.
- Prerequisite: Phase 0 Task 1 complete (package skeleton exists and `swift test` runs).

---

### Task 1: Core domain model

**Files:**
- Create: `Sources/RoundPlayEngine/Model/Course.swift`
- Create: `Sources/RoundPlayEngine/Model/Seat.swift`
- Create: `Sources/RoundPlayEngine/Model/ScoreEvent.swift`
- Create: `Sources/RoundPlayEngine/Model/GameType.swift`
- Test: `Tests/RoundPlayEngineTests/Model/CourseTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Hole(number:par:strokeIndex:)`, `Course(id:name:holes:)` with `Course.hole(_ number: Int) -> Hole?`, `Seat(playerID:name:courseHandicap:)`, `ScoreEvent(id:hole:playerID:payload:enteredBy:sequence:)`, `ScoreEventPayload` (`.strokes`, `.wolfDeclaration`, `.holeEvent`), `WolfDeclaration` (`.partner(UUID)`, `.lone`), `HoleEventKind` (`.bingo`, `.bango`, `.bongo`), `GameType`, `InputKind`.

- [ ] **Step 1: Write the failing test**

Create `Tests/RoundPlayEngineTests/Model/CourseTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

@Test("Course looks up holes by number")
func courseLooksUpHoles() throws {
    let course = Course.testPar72
    #expect(course.hole(1)?.par == 4)
    #expect(course.hole(18)?.par == 4)
    #expect(course.hole(19) == nil)
}

@Test("Course rejects a duplicate stroke index")
func courseValidatesStrokeIndexes() {
    let bad = (1...18).map { Hole(number: $0, par: 4, strokeIndex: 1) }
    #expect(throws: CourseValidationError.duplicateStrokeIndex) {
        try Course.validated(id: UUID(), name: "Bad", holes: bad)
    }
}

@Test("Course requires 18 holes")
func courseRequiresEighteenHoles() {
    let short = (1...9).map { Hole(number: $0, par: 4, strokeIndex: $0) }
    #expect(throws: CourseValidationError.wrongHoleCount) {
        try Course.validated(id: UUID(), name: "Short", holes: short)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: FAIL — `cannot find 'Course' in scope`.

- [ ] **Step 3: Write `Course.swift`**

```swift
import Foundation

/// One hole on a course.
///
/// `strokeIndex` is the hole's difficulty rank, 1 (hardest) through 18 (easiest). It is printed on
/// every physical scorecard and is what handicap strokes are allocated against — without it,
/// net play is impossible.
public struct Hole: Equatable, Sendable, Codable {
    public let number: Int
    public let par: Int
    public let strokeIndex: Int

    public init(number: Int, par: Int, strokeIndex: Int) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
    }
}

public enum CourseValidationError: Error, Equatable, Sendable {
    case wrongHoleCount
    case duplicateStrokeIndex
    case strokeIndexOutOfRange
    case nonSequentialHoleNumbers
    case implausiblePar
}

/// A golf course: a name and 18 holes with par and stroke index.
///
/// Created by whoever plays it first and shared globally thereafter, so validation is strict —
/// one person's typo would otherwise propagate to every future group at that course.
public struct Course: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let holes: [Hole]

    public init(id: UUID, name: String, holes: [Hole]) {
        self.id = id
        self.name = name
        self.holes = holes
    }

    public func hole(_ number: Int) -> Hole? {
        holes.first { $0.number == number }
    }

    public var totalPar: Int { holes.reduce(0) { $0 + $1.par } }

    /// Front nine is holes 1–9, back nine 10–18.
    public func holes(in segment: RoundSegment) -> [Hole] {
        holes.filter { segment.contains(hole: $0.number) }
    }

    /// Validating factory. Use this for anything user-entered.
    public static func validated(id: UUID, name: String, holes: [Hole]) throws -> Course {
        guard holes.count == 18 else { throw CourseValidationError.wrongHoleCount }
        guard Set(holes.map(\.number)) == Set(1...18) else {
            throw CourseValidationError.nonSequentialHoleNumbers
        }
        let indexes = holes.map(\.strokeIndex)
        guard indexes.allSatisfy({ (1...18).contains($0) }) else {
            throw CourseValidationError.strokeIndexOutOfRange
        }
        guard Set(indexes).count == 18 else { throw CourseValidationError.duplicateStrokeIndex }
        guard holes.allSatisfy({ (3...6).contains($0.par) }) else {
            throw CourseValidationError.implausiblePar
        }
        return Course(id: id, name: name, holes: holes.sorted { $0.number < $1.number })
    }
}

/// Which stretch of the round a bet covers. Nassau needs all three.
public enum RoundSegment: String, Equatable, Sendable, Codable, CaseIterable {
    case front
    case back
    case total

    public func contains(hole: Int) -> Bool {
        switch self {
        case .front: (1...9).contains(hole)
        case .back: (10...18).contains(hole)
        case .total: (1...18).contains(hole)
        }
    }

    public var displayName: String {
        switch self {
        case .front: "Front 9"
        case .back: "Back 9"
        case .total: "Total 18"
        }
    }
}
```

- [ ] **Step 4: Write `Seat.swift`**

```swift
import Foundation

/// A player's place in a round.
///
/// `courseHandicap` is frozen at round-creation time rather than read live from the player record,
/// so a settled round always recomputes to the same money even after the player's handicap changes.
public struct Seat: Equatable, Sendable, Codable, Identifiable {
    public let playerID: UUID
    public let name: String
    public let courseHandicap: Int

    public var id: UUID { playerID }

    public init(playerID: UUID, name: String, courseHandicap: Int) {
        self.playerID = playerID
        self.name = name
        self.courseHandicap = courseHandicap
    }
}
```

- [ ] **Step 5: Write `ScoreEvent.swift`**

```swift
import Foundation

/// What a player recorded on a hole.
public enum ScoreEventPayload: Equatable, Sendable, Codable {
    /// Gross strokes taken. The overwhelmingly common case.
    case strokes(Int)
    /// Wolf's per-hole choice. The `playerID` on the event is the Wolf.
    case wolfDeclaration(WolfDeclaration)
    /// Bingo Bango Bongo point. The `playerID` on the event is who earned it.
    case holeEvent(HoleEventKind)
}

/// The Wolf's decision for a hole: take a partner, or play the field alone.
public enum WolfDeclaration: Equatable, Sendable, Codable {
    case partner(UUID)
    case lone
}

/// The three Bingo Bango Bongo points.
public enum HoleEventKind: String, Equatable, Sendable, Codable, CaseIterable {
    /// First ball on the green.
    case bingo
    /// Closest to the pin once every ball is on the green.
    case bango
    /// First in the hole.
    case bongo
}

/// One append-only entry in a round's log.
///
/// Scores are never overwritten. A correction appends a new event with a higher `sequence`;
/// the earlier one stays for the audit trail. This is why "who changed my score on 14" is a
/// query rather than a feature, and why offline sync needs no merge logic.
public struct ScoreEvent: Equatable, Sendable, Codable, Identifiable {
    /// Client-generated, stable across retries. Makes a flaky connection's duplicate POST a no-op.
    public let id: UUID
    public let hole: Int
    /// Who the event is *about* — not who typed it.
    public let playerID: UUID
    public let payload: ScoreEventPayload
    /// Who typed it. Drives the audit view; may differ from `playerID` when one person keeps score.
    public let enteredBy: UUID
    /// Authoritative ordering. Assigned by the server in Phase 2; monotonic per-device in Phase 1.
    public let sequence: Int

    public init(
        id: UUID,
        hole: Int,
        playerID: UUID,
        payload: ScoreEventPayload,
        enteredBy: UUID,
        sequence: Int
    ) {
        self.id = id
        self.hole = hole
        self.playerID = playerID
        self.payload = payload
        self.enteredBy = enteredBy
        self.sequence = sequence
    }
}
```

- [ ] **Step 6: Write `GameType.swift`**

```swift
import Foundation

/// The six launch games.
public enum GameType: String, Equatable, Sendable, Codable, CaseIterable {
    case skins
    case nassau
    case stableford
    case nines
    case wolf
    case bingoBangoBongo
}

/// What a game needs the scorecard UI to collect beyond gross strokes.
///
/// The hole screen renders prompts from this set. It does not know what Wolf *is* — it knows
/// that a game declaring `.partnerChoice` needs a partner picker before scores are entered.
public enum InputKind: String, Equatable, Sendable, Codable, CaseIterable {
    case strokes
    case partnerChoice
    case holeEvents
}

/// Static facts about a game, used to build the library screen and drive the scorecard UI.
public protocol GameDescriptor {
    static var gameType: GameType { get }
    static var displayName: String { get }
    /// One line, plain English, written for someone who has never played it.
    static var summary: String { get }
    static var requiredInputs: Set<InputKind> { get }
    static var playerRange: ClosedRange<Int> { get }
}
```

- [ ] **Step 7: Add the shared test fixture course**

Create `Tests/RoundPlayEngineTests/Support/TestCourse.swift`:

```swift
import Foundation
@testable import RoundPlayEngine

extension Course {
    /// A conventional par-72 layout used across engine tests.
    ///
    /// Stroke indexes follow the usual convention: odds on the front nine, evens on the back,
    /// so a 9-handicap gets a shot on every front-nine hole and none on the back.
    static var testPar72: Course {
        let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4,
                    4, 3, 5, 4, 4, 3, 5, 4, 4]
        let strokeIndexes = [1, 11, 17, 3, 7, 15, 13, 5, 9,
                             2, 16, 12, 4, 8, 18, 14, 6, 10]
        let holes = (0..<18).map {
            Hole(number: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0])
        }
        return Course(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!,
                      name: "Test Par 72",
                      holes: holes)
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: PASS — 4 tests (3 new + the Phase 0 smoke test).

- [ ] **Step 9: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add core domain model"
```

---

### Task 2: Handicap allocation and round state resolution

**Files:**
- Create: `Sources/RoundPlayEngine/Scoring/HandicapAllocation.swift`
- Create: `Sources/RoundPlayEngine/Scoring/RoundState.swift`
- Test: `Tests/RoundPlayEngineTests/Scoring/HandicapAllocationTests.swift`
- Test: `Tests/RoundPlayEngineTests/Scoring/RoundStateTests.swift`

**Interfaces:**
- Consumes: `Course`, `Hole`, `Seat`, `ScoreEvent` from Task 1.
- Produces: `HandicapAllocation.strokesReceived(courseHandicap:strokeIndex:) -> Int`, `RoundState(log:seats:course:)` with `gross(hole:player:) -> Int?`, `net(hole:player:) -> Int?`, `strokesReceived(hole:player:) -> Int`, `wolfDeclaration(hole:) -> (wolf: UUID, declaration: WolfDeclaration)?`, `holeEventWinner(hole:kind:) -> UUID?`, `isComplete(hole:) -> Bool`, `completedHoles(in:) -> [Int]`, `latestEvents -> [ScoreEvent]`.

- [ ] **Step 1: Write the failing handicap test**

Create `Tests/RoundPlayEngineTests/Scoring/HandicapAllocationTests.swift`:

```swift
import Testing
@testable import RoundPlayEngine

@Test("Scratch player receives no strokes")
func scratchGetsNothing() {
    for si in 1...18 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 0, strokeIndex: si) == 0)
    }
}

@Test("A 12 handicap gets one stroke on the twelve hardest holes")
func twelveHandicapAllocation() {
    for si in 1...12 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 12, strokeIndex: si) == 1)
    }
    for si in 13...18 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 12, strokeIndex: si) == 0)
    }
}

@Test("A 22 handicap gets a second stroke on the four hardest holes")
func twentyTwoHandicapAllocation() {
    for si in 1...4 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 22, strokeIndex: si) == 2)
    }
    for si in 5...18 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 22, strokeIndex: si) == 1)
    }
}

@Test("Exactly 36 gives two strokes everywhere")
func thirtySixHandicapAllocation() {
    for si in 1...18 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 36, strokeIndex: si) == 2)
    }
}

@Test("Total strokes allocated equals the course handicap")
func allocationSumsToHandicap() {
    for handicap in 0...54 {
        let total = (1...18).reduce(0) {
            $0 + HandicapAllocation.strokesReceived(courseHandicap: handicap, strokeIndex: $1)
        }
        #expect(total == handicap, "handicap \(handicap) allocated \(total) strokes")
    }
}

@Test("Plus handicaps are treated as scratch in Phase 1")
func plusHandicapsClampToScratch() {
    #expect(HandicapAllocation.strokesReceived(courseHandicap: -3, strokeIndex: 1) == 0)
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: FAIL — `cannot find 'HandicapAllocation' in scope`.

- [ ] **Step 3: Write `HandicapAllocation.swift`**

```swift
import Foundation

/// Distributes a course handicap across 18 holes by stroke index.
///
/// The rule every scorecard uses: a handicap of 12 means one stroke on the twelve hardest holes
/// (stroke index 1–12). Above 18 it wraps — a 22 gets one stroke everywhere plus a second on
/// stroke index 1–4.
///
/// **Plus handicaps (better than scratch) are out of scope for Phase 1** and clamp to zero.
/// They are a fraction of a percent of golfers and the convention for giving strokes back is not
/// uniform across clubs; guessing it would silently produce wrong money. Revisit with a real
/// plus-handicap tester.
public enum HandicapAllocation {
    public static let holeCount = 18

    public static func strokesReceived(courseHandicap: Int, strokeIndex: Int) -> Int {
        guard courseHandicap > 0 else { return 0 }
        let base = courseHandicap / holeCount
        let remainder = courseHandicap % holeCount
        return base + (strokeIndex <= remainder ? 1 : 0)
    }
}
```

- [ ] **Step 4: Run to verify the handicap tests pass**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: PASS.

- [ ] **Step 5: Write the failing round state test**

Create `Tests/RoundPlayEngineTests/Scoring/RoundStateTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

private let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000A11C7")!
private let bob = UUID(uuidString: "00000000-0000-0000-0000-0000000000B0B")!

private func seats() -> [Seat] {
    [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 18)
    ]
}

private func strokeEvent(
    hole: Int, player: UUID, strokes: Int, by: UUID, seq: Int
) -> ScoreEvent {
    ScoreEvent(
        id: UUID(), hole: hole, playerID: player,
        payload: .strokes(strokes), enteredBy: by, sequence: seq
    )
}

@Test("Latest event by sequence wins for a hole and player")
func latestEventWins() {
    let log = [
        strokeEvent(hole: 1, player: alice, strokes: 6, by: bob, seq: 1),
        strokeEvent(hole: 1, player: alice, strokes: 5, by: bob, seq: 2)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.gross(hole: 1, player: alice) == 5)
}

@Test("Out-of-order sequences still resolve to the highest")
func outOfOrderResolves() {
    let log = [
        strokeEvent(hole: 1, player: alice, strokes: 5, by: bob, seq: 9),
        strokeEvent(hole: 1, player: alice, strokes: 6, by: bob, seq: 2)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.gross(hole: 1, player: alice) == 5)
}

@Test("Net subtracts allocated handicap strokes")
func netAppliesHandicap() {
    // Hole 1 is stroke index 1; an 18 handicap gets a shot on every hole.
    let log = [
        strokeEvent(hole: 1, player: bob, strokes: 6, by: bob, seq: 1)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.gross(hole: 1, player: bob) == 6)
    #expect(state.strokesReceived(hole: 1, player: bob) == 1)
    #expect(state.net(hole: 1, player: bob) == 5)
}

@Test("A hole is complete only when every seat has a score")
func completenessRequiresAllSeats() {
    let log = [strokeEvent(hole: 1, player: alice, strokes: 4, by: alice, seq: 1)]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.isComplete(hole: 1) == false)

    let full = log + [strokeEvent(hole: 1, player: bob, strokes: 5, by: alice, seq: 2)]
    let complete = RoundState(log: full, seats: seats(), course: .testPar72)
    #expect(complete.isComplete(hole: 1) == true)
    #expect(complete.completedHoles(in: .total) == [1])
}

@Test("Wolf declarations and hole events resolve independently of strokes")
func nonStrokePayloadsResolve() {
    let log = [
        ScoreEvent(id: UUID(), hole: 3, playerID: alice,
                   payload: .wolfDeclaration(.partner(bob)), enteredBy: alice, sequence: 1),
        ScoreEvent(id: UUID(), hole: 3, playerID: bob,
                   payload: .holeEvent(.bingo), enteredBy: alice, sequence: 2)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.wolfDeclaration(hole: 3)?.wolf == alice)
    #expect(state.wolfDeclaration(hole: 3)?.declaration == .partner(bob))
    #expect(state.holeEventWinner(hole: 3, kind: .bingo) == bob)
    #expect(state.holeEventWinner(hole: 3, kind: .bango) == nil)
}
```

- [ ] **Step 6: Run to verify it fails**

Expected: FAIL — `cannot find 'RoundState' in scope`.

- [ ] **Step 7: Write `RoundState.swift`**

```swift
import Foundation

/// The append-only event log folded into current values.
///
/// This is the single place the log→state reduction happens. Every engine reads `RoundState`
/// and never touches raw events, so "latest sequence wins" is defined exactly once.
public struct RoundState: Sendable {
    public let seats: [Seat]
    public let course: Course

    /// Highest-sequence stroke entry per (hole, player).
    private let strokesByHolePlayer: [HolePlayer: Int]
    /// Highest-sequence Wolf declaration per hole.
    private let wolfByHole: [Int: (wolf: UUID, declaration: WolfDeclaration)]
    /// Highest-sequence winner per (hole, event kind).
    private let holeEvents: [HoleEventKey: UUID]

    private struct HolePlayer: Hashable {
        let hole: Int
        let player: UUID
    }

    private struct HoleEventKey: Hashable {
        let hole: Int
        let kind: HoleEventKind
    }

    public init(log: [ScoreEvent], seats: [Seat], course: Course) {
        self.seats = seats
        self.course = course

        // Sorting ascending and letting later writes overwrite gives "highest sequence wins"
        // without a comparison in the loop. Ties on sequence are broken by event id so the
        // fold stays deterministic even if the server ever hands out a duplicate.
        let ordered = log.sorted {
            $0.sequence == $1.sequence
                ? $0.id.uuidString < $1.id.uuidString
                : $0.sequence < $1.sequence
        }

        var strokes: [HolePlayer: Int] = [:]
        var wolf: [Int: (wolf: UUID, declaration: WolfDeclaration)] = [:]
        var events: [HoleEventKey: UUID] = [:]

        for event in ordered {
            switch event.payload {
            case .strokes(let count):
                strokes[HolePlayer(hole: event.hole, player: event.playerID)] = count
            case .wolfDeclaration(let declaration):
                wolf[event.hole] = (wolf: event.playerID, declaration: declaration)
            case .holeEvent(let kind):
                events[HoleEventKey(hole: event.hole, kind: kind)] = event.playerID
            }
        }

        self.strokesByHolePlayer = strokes
        self.wolfByHole = wolf
        self.holeEvents = events
    }

    // MARK: - Scores

    public func gross(hole: Int, player: UUID) -> Int? {
        strokesByHolePlayer[HolePlayer(hole: hole, player: player)]
    }

    public func strokesReceived(hole: Int, player: UUID) -> Int {
        guard let seat = seats.first(where: { $0.playerID == player }),
              let strokeIndex = course.hole(hole)?.strokeIndex else { return 0 }
        return HandicapAllocation.strokesReceived(
            courseHandicap: seat.courseHandicap,
            strokeIndex: strokeIndex
        )
    }

    public func net(hole: Int, player: UUID) -> Int? {
        guard let gross = gross(hole: hole, player: player) else { return nil }
        return gross - strokesReceived(hole: hole, player: player)
    }

    // MARK: - Non-stroke inputs

    public func wolfDeclaration(hole: Int) -> (wolf: UUID, declaration: WolfDeclaration)? {
        wolfByHole[hole]
    }

    public func holeEventWinner(hole: Int, kind: HoleEventKind) -> UUID? {
        holeEvents[HoleEventKey(hole: hole, kind: kind)]
    }

    // MARK: - Completeness

    /// A hole counts only when every seat has a stroke entry. Partial holes are skipped by every
    /// engine so a round in progress settles correctly rather than treating a blank as a zero.
    public func isComplete(hole: Int) -> Bool {
        seats.allSatisfy { gross(hole: hole, player: $0.playerID) != nil }
    }

    public func completedHoles(in segment: RoundSegment) -> [Int] {
        (1...18).filter { segment.contains(hole: $0) && isComplete(hole: $0) }
    }

    // MARK: - Helpers for engines

    /// Seats sorted by net score on a hole, lowest first. Only complete holes should be passed.
    func seatsRankedByNet(hole: Int) -> [(seat: Seat, net: Int)] {
        seats
            .compactMap { seat in net(hole: hole, player: seat.playerID).map { (seat, $0) } }
            .sorted { $0.1 < $1.1 }
    }
}
```

- [ ] **Step 8: Run to verify all tests pass**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: PASS — 11 tests.

- [ ] **Step 9: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add handicap allocation and round state resolution"
```

---

### Task 3: Settlement types and the zero-sum invariant

**Files:**
- Create: `Sources/RoundPlayEngine/Scoring/Settlement.swift`
- Test: `Tests/RoundPlayEngineTests/Scoring/SettlementTests.swift`

**Interfaces:**
- Consumes: `GameType` from Task 1.
- Produces: `Settlement(gameType:standings:holeExplanations:)`, `PlayerStanding(playerID:points:money:)`, `HoleExplanation(hole:text:)`, `Settlement.isZeroSum`, `Settlement.money(for:) -> Decimal`, and `Settlement.distributingPot(...)` used by point-based games.

- [ ] **Step 1: Write the failing test**

Create `Tests/RoundPlayEngineTests/Scoring/SettlementTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(), b = UUID(), c = UUID()

@Test("A balanced settlement is zero-sum")
func balancedIsZeroSum() {
    let settlement = Settlement(
        gameType: .skins,
        standings: [
            PlayerStanding(playerID: a, points: 2, money: 10),
            PlayerStanding(playerID: b, points: 0, money: -10)
        ],
        holeExplanations: []
    )
    #expect(settlement.isZeroSum)
    #expect(settlement.money(for: a) == 10)
    #expect(settlement.money(for: c) == 0)
}

@Test("An unbalanced settlement is caught")
func unbalancedIsDetected() {
    let settlement = Settlement(
        gameType: .skins,
        standings: [
            PlayerStanding(playerID: a, points: 2, money: 10),
            PlayerStanding(playerID: b, points: 0, money: -5)
        ],
        holeExplanations: []
    )
    #expect(settlement.isZeroSum == false)
}

@Test("Point-difference settlement pays each pair the unit stake per point")
func pointDifferenceSettles() {
    // a: 10 pts, b: 6 pts, c: 2 pts. At $1/point:
    // a collects (10-6) + (10-2) = 12; b collects (6-10) + (6-2) = 0; c: (2-10)+(2-6) = -12
    let money = Settlement.pointDifferenceMoney(
        points: [a: 10, b: 6, c: 2],
        unitStake: 1
    )
    #expect(money[a] == 12)
    #expect(money[b] == 0)
    #expect(money[c] == -12)
    #expect(money.values.reduce(0, +) == 0)
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `cannot find 'Settlement' in scope`.

- [ ] **Step 3: Write `Settlement.swift`**

```swift
import Foundation

/// One player's result in one game.
public struct PlayerStanding: Equatable, Sendable, Codable, Identifiable {
    public let playerID: UUID
    /// Game-native units: skins won, match holes up, Stableford points, Wolf points.
    public let points: Int
    /// Positive means the player collects; negative means they pay.
    public let money: Decimal

    public var id: UUID { playerID }

    public init(playerID: UUID, points: Int, money: Decimal) {
        self.playerID = playerID
        self.points = points
        self.money = money
    }
}

/// A plain-English account of what happened on one hole.
///
/// Every dollar in a settlement must be traceable to one of these. This is the feature that ends
/// the 19th-hole argument, so it is part of the return type rather than a debugging afterthought.
public struct HoleExplanation: Equatable, Sendable, Codable {
    public let hole: Int
    public let text: String

    public init(hole: Int, text: String) {
        self.hole = hole
        self.text = text
    }
}

/// The result of settling one game over one round.
public struct Settlement: Equatable, Sendable, Codable {
    public let gameType: GameType
    public let standings: [PlayerStanding]
    public let holeExplanations: [HoleExplanation]

    public init(
        gameType: GameType,
        standings: [PlayerStanding],
        holeExplanations: [HoleExplanation]
    ) {
        self.gameType = gameType
        self.standings = standings
        self.holeExplanations = holeExplanations
    }

    public func money(for player: UUID) -> Decimal {
        standings.first { $0.playerID == player }?.money ?? 0
    }

    public func points(for player: UUID) -> Int {
        standings.first { $0.playerID == player }?.points ?? 0
    }

    /// Money must net to exactly zero — nobody conjures a dollar and none leaks out.
    /// Asserted in every engine's test suite.
    public var isZeroSum: Bool {
        standings.reduce(Decimal(0)) { $0 + $1.money } == 0
    }

    /// Settles a points-based game where every player pays every other player the unit stake for
    /// each point of difference between them. This is how Nines, Stableford, Wolf, and Bingo Bango
    /// Bongo convert points to money, and it is zero-sum by construction.
    public static func pointDifferenceMoney(
        points: [UUID: Int],
        unitStake: Decimal
    ) -> [UUID: Decimal] {
        var money: [UUID: Decimal] = [:]
        for (player, own) in points {
            let total = points.reduce(0) { partial, other in
                other.key == player ? partial : partial + (own - other.value)
            }
            money[player] = Decimal(total) * unitStake
        }
        return money
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: PASS — 14 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add settlement types and zero-sum invariant"
```

---

### Task 4: Skins

**Files:**
- Create: `Sources/RoundPlayEngine/Games/SkinsEngine.swift`
- Test: `Tests/RoundPlayEngineTests/Games/SkinsEngineTests.swift`

**Interfaces:**
- Consumes: `RoundState`, `Settlement`, `GameDescriptor` from Tasks 1–3.
- Produces: `SkinsEngine.settle(state:config:) -> Settlement`, `SkinsConfig(unitStake:carryOverTies:)`.

**Rule:** each hole is worth one skin at the unit stake. Lowest net score wins it outright. A tie carries the pot to the next hole and it accumulates. Skins won are paid by every other player at the unit stake per skin.

- [ ] **Step 1: Write the failing test**

Create `Tests/RoundPlayEngineTests/Games/SkinsEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

private let alice = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
private let bob = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
private let carol = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!

private func scratchSeats() -> [Seat] {
    [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 0),
        Seat(playerID: carol, name: "Carol", courseHandicap: 0)
    ]
}

/// Builds a log from `[hole: [player: grossStrokes]]`.
private func log(_ holes: [Int: [UUID: Int]]) -> [ScoreEvent] {
    var events: [ScoreEvent] = []
    var seq = 0
    for hole in holes.keys.sorted() {
        for (player, strokes) in holes[hole]!.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            seq += 1
            events.append(ScoreEvent(
                id: UUID(), hole: hole, playerID: player,
                payload: .strokes(strokes), enteredBy: alice, sequence: seq
            ))
        }
    }
    return events
}

@Test("Outright low score wins the skin")
func outrightWinTakesSkin() {
    let state = RoundState(
        log: log([1: [alice: 4, bob: 5, carol: 5]]),
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.points(for: alice) == 1)
    // Alice collects the unit from each of the two others.
    #expect(result.money(for: alice) == 10)
    #expect(result.money(for: bob) == -5)
    #expect(result.isZeroSum)
}

@Test("A tie carries the skin to the next hole")
func tieCarriesOver() {
    let state = RoundState(
        log: log([
            1: [alice: 4, bob: 4, carol: 5],   // tied — carries
            2: [alice: 3, bob: 5, carol: 5]    // Alice wins 2 skins
        ]),
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.points(for: alice) == 2)
    #expect(result.money(for: alice) == 20)
    #expect(result.isZeroSum)
}

@Test("Carryover is announced in the hole explanation")
func explanationMentionsCarryover() {
    let state = RoundState(
        log: log([
            1: [alice: 4, bob: 4, carol: 5],
            2: [alice: 3, bob: 5, carol: 5]
        ]),
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))
    let hole2 = result.holeExplanations.first { $0.hole == 2 }

    #expect(hole2?.text.contains("2 skins") == true)
    #expect(hole2?.text.contains("carryover") == true)
}

@Test("Handicap strokes decide the skin on net score")
func netScoreDecidesSkin() {
    let seats = [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 18),
        Seat(playerID: carol, name: "Carol", courseHandicap: 0)
    ]
    // Hole 1: Alice 4 gross (net 4), Bob 5 gross (net 4 with his shot), Carol 6.
    // Alice and Bob tie on net, so the skin carries — gross alone would have given it to Alice.
    let state = RoundState(
        log: log([1: [alice: 4, bob: 5, carol: 6]]),
        seats: seats, course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.points(for: alice) == 0)
    #expect(result.money(for: alice) == 0)
    #expect(result.isZeroSum)
}

@Test("Incomplete holes are skipped rather than treated as zeroes")
func incompleteHolesAreSkipped() {
    let state = RoundState(
        log: log([1: [alice: 4, bob: 5]]),   // Carol has no score
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.standings.allSatisfy { $0.points == 0 })
    #expect(result.isZeroSum)
}

@Test("Unclaimed skins at the end of the round are not paid out")
func unclaimedSkinsExpire() {
    let state = RoundState(
        log: log([1: [alice: 4, bob: 4, carol: 5]]),   // ties, carries, round ends
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.standings.allSatisfy { $0.money == 0 })
    #expect(result.isZeroSum)
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `cannot find 'SkinsEngine' in scope`.

- [ ] **Step 3: Write `SkinsEngine.swift`**

```swift
import Foundation

public struct SkinsConfig: Equatable, Sendable, Codable {
    /// Value of one skin, per opponent.
    public let unitStake: Decimal
    /// When true (the default and near-universal rule), a tied hole rolls its skin forward.
    public let carryOverTies: Bool

    public init(unitStake: Decimal, carryOverTies: Bool = true) {
        self.unitStake = unitStake
        self.carryOverTies = carryOverTies
    }
}

/// Skins: each hole is worth one skin, won outright by the lowest net score.
///
/// Ties carry the pot forward, which is what produces the big swings late in a round. Skins left
/// unclaimed when the round ends are **not** paid — the money was never won. Groups that prefer
/// to split the leftover do so in cash at the bar; encoding it here would mean inventing a rule
/// the group did not agree to.
public enum SkinsEngine: GameDescriptor {
    public static let gameType: GameType = .skins
    public static let displayName = "Skins"
    public static let summary = "Every hole is worth a skin. Win the hole outright to take it — tie and it rolls over."
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 2...8

    public static func settle(state: RoundState, config: SkinsConfig) -> Settlement {
        var skinsWon: [UUID: Int] = [:]
        var explanations: [HoleExplanation] = []
        var carried = 0

        for hole in state.completedHoles(in: .total) {
            let ranked = state.seatsRankedByNet(hole: hole)
            guard let best = ranked.first else { continue }

            let atBest = ranked.filter { $0.net == best.net }
            let potThisHole = carried + 1

            if atBest.count == 1 || !config.carryOverTies {
                let winner = atBest[0].seat
                skinsWon[winner.playerID, default: 0] += potThisHole
                carried = 0

                let plural = potThisHole == 1 ? "skin" : "skins"
                let value = config.unitStake * Decimal(potThisHole)
                    * Decimal(max(state.seats.count - 1, 0))
                let carryNote = potThisHole > 1 ? " — carryover from earlier" : ""
                explanations.append(HoleExplanation(
                    hole: hole,
                    text: "Hole \(hole): \(winner.name) wins \(potThisHole) \(plural) "
                        + "(\(formatted(value)))\(carryNote)."
                ))
            } else {
                carried = potThisHole
                let names = atBest.map(\.seat.name).joined(separator: " and ")
                explanations.append(HoleExplanation(
                    hole: hole,
                    text: "Hole \(hole): \(names) tied at net \(best.net). "
                        + "\(potThisHole) carries to the next hole."
                ))
            }
        }

        // Each skin is collected from every other player at the unit stake.
        let opponents = Decimal(max(state.seats.count - 1, 0))
        let totalSkins = skinsWon.values.reduce(0, +)

        let standings = state.seats.map { seat -> PlayerStanding in
            let won = skinsWon[seat.playerID] ?? 0
            let collected = config.unitStake * Decimal(won) * opponents
            let paid = config.unitStake * Decimal(totalSkins - won)
            return PlayerStanding(
                playerID: seat.playerID,
                points: won,
                money: collected - paid
            )
        }

        return Settlement(
            gameType: gameType,
            standings: standings,
            holeExplanations: explanations
        )
    }

    private static func formatted(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}
```

Note on the money math: a player who wins `w` of `t` total skins collects `unitStake × w × opponents` and pays `unitStake × (t − w)`. Summed across all players this cancels exactly, which is what the zero-sum test verifies.

- [ ] **Step 4: Run to verify it passes**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: PASS — 20 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add Skins"
```

---

### Task 5: Stableford

**Files:**
- Create: `Sources/RoundPlayEngine/Games/StablefordEngine.swift`
- Test: `Tests/RoundPlayEngineTests/Games/StablefordEngineTests.swift`

**Interfaces:**
- Consumes: `RoundState`, `Settlement`, `Settlement.pointDifferenceMoney` from Tasks 2–3.
- Produces: `StablefordEngine.settle(state:config:) -> Settlement`, `StablefordConfig(unitStake:pointsTable:)`, `StablefordConfig.standard`, `StablefordConfig.modified`.

**Rule:** points against net par. Standard table: double bogey or worse 0, bogey 1, par 2, birdie 3, eagle 4, albatross 5. Money settles by point difference at the unit stake.

- [ ] **Step 1: Write the failing test**

Create `Tests/RoundPlayEngineTests/Games/StablefordEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

private let alice = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
private let bob = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

private func seats() -> [Seat] {
    [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 0)
    ]
}

private func log(_ holes: [Int: [UUID: Int]]) -> [ScoreEvent] {
    var events: [ScoreEvent] = []
    var seq = 0
    for hole in holes.keys.sorted() {
        for (player, strokes) in holes[hole]!.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            seq += 1
            events.append(ScoreEvent(id: UUID(), hole: hole, playerID: player,
                                     payload: .strokes(strokes), enteredBy: alice, sequence: seq))
        }
    }
    return events
}

@Test("Standard point table maps net score to points")
func standardPointTable() {
    let table = StablefordConfig.standard.pointsTable
    #expect(table.points(netRelativeToPar: 2) == 0)    // double bogey
    #expect(table.points(netRelativeToPar: 3) == 0)    // worse still
    #expect(table.points(netRelativeToPar: 1) == 1)    // bogey
    #expect(table.points(netRelativeToPar: 0) == 2)    // par
    #expect(table.points(netRelativeToPar: -1) == 3)   // birdie
    #expect(table.points(netRelativeToPar: -2) == 4)   // eagle
    #expect(table.points(netRelativeToPar: -3) == 5)   // albatross
}

@Test("Points accumulate across holes and settle on the difference")
func pointsAccumulateAndSettle() {
    // Hole 1 par 4: Alice 3 (birdie, 3pts), Bob 4 (par, 2pts)
    // Hole 2 par 5: Alice 5 (par, 2pts), Bob 7 (double, 0pts)
    let state = RoundState(
        log: log([1: [alice: 3, bob: 4], 2: [alice: 5, bob: 7]]),
        seats: seats(), course: .testPar72
    )
    let result = StablefordEngine.settle(
        state: state,
        config: StablefordConfig(unitStake: 2, pointsTable: .standard)
    )

    #expect(result.points(for: alice) == 5)
    #expect(result.points(for: bob) == 2)
    // Difference of 3 points at $2 = $6 from Bob to Alice.
    #expect(result.money(for: alice) == 6)
    #expect(result.money(for: bob) == -6)
    #expect(result.isZeroSum)
}

@Test("Handicap strokes raise a bogey to a par for points")
func handicapAffectsPoints() {
    let seats = [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 18)
    ]
    // Hole 1 par 4: Bob shoots 5 gross, nets 4 with his shot — a par, worth 2 points.
    let state = RoundState(log: log([1: [alice: 4, bob: 5]]), seats: seats, course: .testPar72)
    let result = StablefordEngine.settle(
        state: state, config: StablefordConfig(unitStake: 1, pointsTable: .standard)
    )

    #expect(result.points(for: bob) == 2)
    #expect(result.points(for: alice) == 2)
    #expect(result.money(for: alice) == 0)
    #expect(result.isZeroSum)
}

@Test("Modified Stableford penalises blowups instead of flooring at zero")
func modifiedTablePenalises() {
    let table = StablefordConfig.modified.pointsTable
    #expect(table.points(netRelativeToPar: 1) == -1)
    #expect(table.points(netRelativeToPar: 2) == -3)
    #expect(table.points(netRelativeToPar: 0) == 0)
    #expect(table.points(netRelativeToPar: -1) == 2)
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `cannot find 'StablefordConfig' in scope`.

- [ ] **Step 3: Write `StablefordEngine.swift`**

```swift
import Foundation

/// Maps a net score relative to par onto points.
///
/// Stored as explicit boundaries rather than a formula because the variants genuinely differ in
/// shape: standard floors at zero, Modified goes negative. A group that plays its own table gets
/// it by constructing one, not by us adding a case.
public struct StablefordPointsTable: Equatable, Sendable, Codable {
    /// Points for each net-relative-to-par value, best first.
    /// Index 0 is albatross (−3), 1 eagle (−2), 2 birdie (−1), 3 par (0), 4 bogey (+1), 5 double (+2).
    public let byRelativeScore: [Int: Int]
    /// Applied to anything worse than the worst listed entry.
    public let floorPoints: Int

    public init(byRelativeScore: [Int: Int], floorPoints: Int) {
        self.byRelativeScore = byRelativeScore
        self.floorPoints = floorPoints
    }

    public func points(netRelativeToPar: Int) -> Int {
        if let exact = byRelativeScore[netRelativeToPar] { return exact }
        // Better than the best listed entry scores the best listed value; worse hits the floor.
        guard let best = byRelativeScore.keys.min(), let worst = byRelativeScore.keys.max() else {
            return floorPoints
        }
        if netRelativeToPar < best { return byRelativeScore[best] ?? floorPoints }
        if netRelativeToPar > worst { return floorPoints }
        return floorPoints
    }

    /// Bogey 1, par 2, birdie 3, eagle 4, albatross 5; double bogey or worse scores nothing.
    public static let standard = StablefordPointsTable(
        byRelativeScore: [-3: 5, -2: 4, -1: 3, 0: 2, 1: 1, 2: 0],
        floorPoints: 0
    )

    /// The tour variant: eagle 5, birdie 2, par 0, bogey −1, double or worse −3.
    public static let modified = StablefordPointsTable(
        byRelativeScore: [-3: 8, -2: 5, -1: 2, 0: 0, 1: -1, 2: -3],
        floorPoints: -3
    )
}

public struct StablefordConfig: Equatable, Sendable, Codable {
    public let unitStake: Decimal
    public let pointsTable: StablefordPointsTable

    public init(unitStake: Decimal, pointsTable: StablefordPointsTable = .standard) {
        self.unitStake = unitStake
        self.pointsTable = pointsTable
    }

    public static let standard = StablefordConfig(unitStake: 1, pointsTable: .standard)
    public static let modified = StablefordConfig(unitStake: 1, pointsTable: .modified)
}

/// Stableford: points against net par, so one disastrous hole costs a point rather than the round.
///
/// This is the reason it is the best format in the library for beginners and for mixed-skill
/// groups — a blowup floors at zero instead of compounding.
public enum StablefordEngine: GameDescriptor {
    public static let gameType: GameType = .stableford
    public static let displayName = "Stableford"
    public static let summary = "Score points per hole instead of counting strokes. A bad hole costs you a point, not your round."
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 2...8

    public static func settle(state: RoundState, config: StablefordConfig) -> Settlement {
        var points: [UUID: Int] = [:]
        for seat in state.seats { points[seat.playerID] = 0 }
        var explanations: [HoleExplanation] = []

        for hole in state.completedHoles(in: .total) {
            guard let par = state.course.hole(hole)?.par else { continue }
            var line: [String] = []

            for seat in state.seats {
                guard let net = state.net(hole: hole, player: seat.playerID) else { continue }
                let earned = config.pointsTable.points(netRelativeToPar: net - par)
                points[seat.playerID, default: 0] += earned
                line.append("\(seat.name) \(earned)")
            }

            explanations.append(HoleExplanation(
                hole: hole,
                text: "Hole \(hole) (par \(par)): " + line.joined(separator: ", ") + "."
            ))
        }

        let money = Settlement.pointDifferenceMoney(points: points, unitStake: config.unitStake)
        let standings = state.seats.map {
            PlayerStanding(
                playerID: $0.playerID,
                points: points[$0.playerID] ?? 0,
                money: money[$0.playerID] ?? 0
            )
        }

        return Settlement(gameType: gameType, standings: standings, holeExplanations: explanations)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: PASS — 24 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add Stableford"
```

---

### Task 6: Nines (5-3-1)

**Files:**
- Create: `Sources/RoundPlayEngine/Games/NinesEngine.swift`
- Test: `Tests/RoundPlayEngineTests/Games/NinesEngineTests.swift`

**Interfaces:**
- Consumes: `RoundState`, `Settlement.pointDifferenceMoney`.
- Produces: `NinesEngine.settle(state:config:) -> Settlement`, `NinesConfig(unitStake:)`, `NinesEngine.SettleError.requiresThreePlayers`.

**Rule:** exactly three players. Nine points per hole: 5 to the lowest net, 3 to the middle, 1 to the highest. Ties: all three tie → 3/3/3; two tie for low → 4/4/1; two tie for high → 5/2/2. Always sums to 9.

- [ ] **Step 1: Write the failing test**

Create `Tests/RoundPlayEngineTests/Games/NinesEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
private let b = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
private let c = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

private func threesome() -> [Seat] {
    [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 0),
        Seat(playerID: c, name: "Cal", courseHandicap: 0)
    ]
}

private func log(_ holes: [Int: [UUID: Int]]) -> [ScoreEvent] {
    var events: [ScoreEvent] = []
    var seq = 0
    for hole in holes.keys.sorted() {
        for (player, strokes) in holes[hole]!.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            seq += 1
            events.append(ScoreEvent(id: UUID(), hole: hole, playerID: player,
                                     payload: .strokes(strokes), enteredBy: a, sequence: seq))
        }
    }
    return events
}

private func settle(_ holes: [Int: [UUID: Int]], stake: Decimal = 1) throws -> Settlement {
    let state = RoundState(log: log(holes), seats: threesome(), course: .testPar72)
    return try NinesEngine.settle(state: state, config: NinesConfig(unitStake: stake))
}

@Test("Clean finish splits 5-3-1")
func cleanFinish() throws {
    let result = try settle([1: [a: 3, b: 4, c: 5]])
    #expect(result.points(for: a) == 5)
    #expect(result.points(for: b) == 3)
    #expect(result.points(for: c) == 1)
    #expect(result.isZeroSum)
}

@Test("All three tied splits 3-3-3")
func allTied() throws {
    let result = try settle([1: [a: 4, b: 4, c: 4]])
    #expect(result.points(for: a) == 3)
    #expect(result.points(for: b) == 3)
    #expect(result.points(for: c) == 3)
    #expect(result.money(for: a) == 0)
}

@Test("Two tied for low splits 4-4-1")
func twoTiedForLow() throws {
    let result = try settle([1: [a: 3, b: 3, c: 5]])
    #expect(result.points(for: a) == 4)
    #expect(result.points(for: b) == 4)
    #expect(result.points(for: c) == 1)
}

@Test("Two tied for high splits 5-2-2")
func twoTiedForHigh() throws {
    let result = try settle([1: [a: 3, b: 5, c: 5]])
    #expect(result.points(for: a) == 5)
    #expect(result.points(for: b) == 2)
    #expect(result.points(for: c) == 2)
}

@Test("Every hole distributes exactly nine points")
func alwaysNinePoints() throws {
    let scenarios: [[UUID: Int]] = [
        [a: 3, b: 4, c: 5], [a: 4, b: 4, c: 4],
        [a: 3, b: 3, c: 5], [a: 3, b: 5, c: 5]
    ]
    for scenario in scenarios {
        let result = try settle([1: scenario])
        let total = result.standings.reduce(0) { $0 + $1.points }
        #expect(total == 9, "scenario \(scenario) gave \(total)")
    }
}

@Test("Nines rejects anything other than three players")
func requiresThreePlayers() {
    let seats = [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 0)
    ]
    let state = RoundState(log: log([1: [a: 4, b: 4]]), seats: seats, course: .testPar72)
    #expect(throws: NinesEngine.SettleError.requiresThreePlayers) {
        try NinesEngine.settle(state: state, config: NinesConfig(unitStake: 1))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `cannot find 'NinesEngine' in scope`.

- [ ] **Step 3: Write `NinesEngine.swift`**

```swift
import Foundation

public struct NinesConfig: Equatable, Sendable, Codable {
    public let unitStake: Decimal

    public init(unitStake: Decimal) {
        self.unitStake = unitStake
    }
}

/// Nines (5-3-1): nine points on every hole, split three ways.
///
/// The only three-player game in the library, which is why it earns its place — a threesome
/// otherwise has nothing but Skins. Ties split the combined points of the places they occupy, so
/// the hole always distributes exactly nine.
public enum NinesEngine: GameDescriptor {
    public static let gameType: GameType = .nines
    public static let displayName = "Nines"
    public static let summary = "Nine points a hole for a threesome: 5 for low, 3 for middle, 1 for high."
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 3...3

    public enum SettleError: Error, Equatable, Sendable {
        case requiresThreePlayers
    }

    public static func settle(state: RoundState, config: NinesConfig) throws -> Settlement {
        guard state.seats.count == 3 else { throw SettleError.requiresThreePlayers }

        var points: [UUID: Int] = [:]
        for seat in state.seats { points[seat.playerID] = 0 }
        var explanations: [HoleExplanation] = []

        for hole in state.completedHoles(in: .total) {
            let ranked = state.seatsRankedByNet(hole: hole)
            guard ranked.count == 3 else { continue }

            let award = pointsForHole(nets: ranked.map(\.net))
            for (index, entry) in ranked.enumerated() {
                points[entry.seat.playerID, default: 0] += award[index]
            }

            let line = zip(ranked, award)
                .map { "\($0.0.seat.name) \($0.1)" }
                .joined(separator: ", ")
            explanations.append(HoleExplanation(hole: hole, text: "Hole \(hole): \(line)."))
        }

        let money = Settlement.pointDifferenceMoney(points: points, unitStake: config.unitStake)
        let standings = state.seats.map {
            PlayerStanding(
                playerID: $0.playerID,
                points: points[$0.playerID] ?? 0,
                money: money[$0.playerID] ?? 0
            )
        }

        return Settlement(gameType: gameType, standings: standings, holeExplanations: explanations)
    }

    /// `nets` must be sorted ascending. Returns the points for each position, always summing to 9.
    static func pointsForHole(nets: [Int]) -> [Int] {
        precondition(nets.count == 3, "Nines scores exactly three players")

        let allTied = nets[0] == nets[2]
        if allTied { return [3, 3, 3] }

        if nets[0] == nets[1] { return [4, 4, 1] }   // two tied for low: (5+3)/2
        if nets[1] == nets[2] { return [5, 2, 2] }   // two tied for high: (3+1)/2
        return [5, 3, 1]
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: PASS — 30 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add Nines"
```

---

### Task 7: Bingo Bango Bongo

**Files:**
- Create: `Sources/RoundPlayEngine/Games/BingoBangoBongoEngine.swift`
- Test: `Tests/RoundPlayEngineTests/Games/BingoBangoBongoEngineTests.swift`

**Interfaces:**
- Consumes: `RoundState.holeEventWinner(hole:kind:)`, `Settlement.pointDifferenceMoney`.
- Produces: `BingoBangoBongoEngine.settle(state:config:) -> Settlement`, `BingoBangoBongoConfig(unitStake:)`.

**Rule:** three points per hole — first ball on the green (bingo), closest to the pin once all balls are on (bango), first in the hole (bongo). Awarded from `.holeEvent` payloads, **not** from stroke counts. Holes with no events recorded contribute nothing.

- [ ] **Step 1: Write the failing test**

Create `Tests/RoundPlayEngineTests/Games/BingoBangoBongoEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
private let b = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!

private func pair() -> [Seat] {
    [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 24)
    ]
}

private func eventLog(_ entries: [(hole: Int, player: UUID, kind: HoleEventKind)]) -> [ScoreEvent] {
    entries.enumerated().map { index, entry in
        ScoreEvent(id: UUID(), hole: entry.hole, playerID: entry.player,
                   payload: .holeEvent(entry.kind), enteredBy: a, sequence: index + 1)
    }
}

@Test("Each recorded event is worth one point")
func eventsScorePoints() {
    let state = RoundState(
        log: eventLog([
            (1, a, .bingo), (1, b, .bango), (1, a, .bongo)
        ]),
        seats: pair(), course: .testPar72
    )
    let result = BingoBangoBongoEngine.settle(
        state: state, config: BingoBangoBongoConfig(unitStake: 1)
    )

    #expect(result.points(for: a) == 2)
    #expect(result.points(for: b) == 1)
    #expect(result.money(for: a) == 1)
    #expect(result.money(for: b) == -1)
    #expect(result.isZeroSum)
}

@Test("Points are independent of stroke counts, so a high handicap can win")
func handicapIsIrrelevant() {
    // Ben is a 24 handicap and takes more strokes, but reaches the green first every time.
    var log = eventLog([
        (1, b, .bingo), (1, b, .bango), (1, b, .bongo),
        (2, b, .bingo), (2, b, .bango), (2, b, .bongo)
    ])
    log.append(ScoreEvent(id: UUID(), hole: 1, playerID: a,
                          payload: .strokes(3), enteredBy: a, sequence: 100))
    log.append(ScoreEvent(id: UUID(), hole: 1, playerID: b,
                          payload: .strokes(8), enteredBy: a, sequence: 101))

    let state = RoundState(log: log, seats: pair(), course: .testPar72)
    let result = BingoBangoBongoEngine.settle(
        state: state, config: BingoBangoBongoConfig(unitStake: 2)
    )

    #expect(result.points(for: b) == 6)
    #expect(result.points(for: a) == 0)
    #expect(result.money(for: b) == 12)
    #expect(result.isZeroSum)
}

@Test("A rewritten event replaces the earlier winner")
func laterEventOverwrites() {
    let log = [
        ScoreEvent(id: UUID(), hole: 1, playerID: a,
                   payload: .holeEvent(.bingo), enteredBy: a, sequence: 1),
        ScoreEvent(id: UUID(), hole: 1, playerID: b,
                   payload: .holeEvent(.bingo), enteredBy: a, sequence: 2)
    ]
    let state = RoundState(log: log, seats: pair(), course: .testPar72)
    let result = BingoBangoBongoEngine.settle(
        state: state, config: BingoBangoBongoConfig(unitStake: 1)
    )

    #expect(result.points(for: b) == 1)
    #expect(result.points(for: a) == 0)
}

@Test("Holes with no events recorded score nothing")
func missingEventsScoreNothing() {
    let state = RoundState(log: [], seats: pair(), course: .testPar72)
    let result = BingoBangoBongoEngine.settle(
        state: state, config: BingoBangoBongoConfig(unitStake: 1)
    )

    #expect(result.standings.allSatisfy { $0.points == 0 && $0.money == 0 })
    #expect(result.isZeroSum)
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `cannot find 'BingoBangoBongoEngine' in scope`.

- [ ] **Step 3: Write `BingoBangoBongoEngine.swift`**

```swift
import Foundation

public struct BingoBangoBongoConfig: Equatable, Sendable, Codable {
    public let unitStake: Decimal

    public init(unitStake: Decimal) {
        self.unitStake = unitStake
    }
}

/// Bingo Bango Bongo: three points a hole for sequence, not skill.
///
/// The only game in the library that ignores stroke counts entirely — points come from
/// `.holeEvent` payloads. That makes it the strongest equalizer available: a 25 handicap who
/// reaches the green first beats a scratch player to the bingo every time.
///
/// It relies on the group playing in order (farthest from the hole plays first). The app cannot
/// enforce that, so the events are recorded on the honour system by whoever is keeping score.
public enum BingoBangoBongoEngine: GameDescriptor {
    public static let gameType: GameType = .bingoBangoBongo
    public static let displayName = "Bingo Bango Bongo"
    public static let summary = "Three points a hole: first on the green, closest to the pin, first in the hole. Handicap doesn't matter."
    public static let requiredInputs: Set<InputKind> = [.holeEvents]
    public static let playerRange = 2...4

    public static func settle(
        state: RoundState,
        config: BingoBangoBongoConfig
    ) -> Settlement {
        var points: [UUID: Int] = [:]
        for seat in state.seats { points[seat.playerID] = 0 }
        var explanations: [HoleExplanation] = []

        for hole in 1...18 {
            var awarded: [String] = []

            for kind in HoleEventKind.allCases {
                guard let winner = state.holeEventWinner(hole: hole, kind: kind) else { continue }
                points[winner, default: 0] += 1
                let name = state.seats.first { $0.playerID == winner }?.name ?? "Unknown"
                awarded.append("\(kind.rawValue) \(name)")
            }

            guard !awarded.isEmpty else { continue }
            explanations.append(HoleExplanation(
                hole: hole,
                text: "Hole \(hole): " + awarded.joined(separator: ", ") + "."
            ))
        }

        let money = Settlement.pointDifferenceMoney(points: points, unitStake: config.unitStake)
        let standings = state.seats.map {
            PlayerStanding(
                playerID: $0.playerID,
                points: points[$0.playerID] ?? 0,
                money: money[$0.playerID] ?? 0
            )
        }

        return Settlement(gameType: gameType, standings: standings, holeExplanations: explanations)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: PASS — 34 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add Bingo Bango Bongo"
```

---

### Task 8: Nassau with presses

**Files:**
- Create: `Sources/RoundPlayEngine/Games/NassauEngine.swift`
- Test: `Tests/RoundPlayEngineTests/Games/NassauEngineTests.swift`

**Interfaces:**
- Consumes: `RoundState`, `RoundSegment`, `Settlement`.
- Produces: `NassauEngine.settle(state:config:) -> Settlement`, `NassauConfig(unitStake:automaticPressAt:)`, `NassauEngine.SettleError.requiresTwoPlayers`.

**Rule:** three match-play bets at the unit stake — front 9, back 9, total 18. Each hole is won by the lower net score; ties halve. A segment pays the unit to whoever is up when it ends; all-square pays nothing. Automatic presses: when a side goes `automaticPressAt` holes down within a segment, a new bet opens on the remaining holes of that segment at the same stake.

**Scope note:** Phase 1 supports **singles only** (exactly two players). The 2v2 best-ball variant needs team assignment, which the Phase 1b UI does not collect. Four-player Nassau is deliberately out of scope here rather than half-built.

- [ ] **Step 1: Write the failing test**

Create `Tests/RoundPlayEngineTests/Games/NassauEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
private let b = UUID(uuidString: "50000000-0000-0000-0000-000000000002")!

private func singles() -> [Seat] {
    [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 0)
    ]
}

/// `aScores` and `bScores` are indexed from hole 1.
private func log(aScores: [Int: Int], bScores: [Int: Int]) -> [ScoreEvent] {
    var events: [ScoreEvent] = []
    var seq = 0
    for hole in Set(aScores.keys).union(bScores.keys).sorted() {
        if let s = aScores[hole] {
            seq += 1
            events.append(ScoreEvent(id: UUID(), hole: hole, playerID: a,
                                     payload: .strokes(s), enteredBy: a, sequence: seq))
        }
        if let s = bScores[hole] {
            seq += 1
            events.append(ScoreEvent(id: UUID(), hole: hole, playerID: b,
                                     payload: .strokes(s), enteredBy: a, sequence: seq))
        }
    }
    return events
}

/// Ann wins holes 1–3, everything else halved.
private func annWinsFrontThree() -> [ScoreEvent] {
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 {
        aScores[hole] = 4
        bScores[hole] = (1...3).contains(hole) ? 5 : 4
    }
    return log(aScores: aScores, bScores: bScores)
}

@Test("Winning the front nine pays one unit")
func frontNinePays() throws {
    let state = RoundState(log: annWinsFrontThree(), seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state,
        config: NassauConfig(unitStake: 10, automaticPressAt: nil)
    )
    // Ann wins front (3 up) and total (3 up); back nine is all square and pays nothing.
    #expect(result.money(for: a) == 20)
    #expect(result.money(for: b) == -20)
    #expect(result.isZeroSum)
}

@Test("An all-square segment pays nothing")
func allSquarePaysNothing() throws {
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 4 }
    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state, config: NassauConfig(unitStake: 10, automaticPressAt: nil)
    )

    #expect(result.money(for: a) == 0)
    #expect(result.money(for: b) == 0)
}

@Test("Net scoring decides holes when handicaps differ")
func netDecidesHoles() throws {
    let seats = [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 18)
    ]
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 5 }   // Ben nets 4 everywhere
    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: seats, course: .testPar72)
    let result = try NassauEngine.settle(
        state: state, config: NassauConfig(unitStake: 10, automaticPressAt: nil)
    )

    #expect(result.money(for: a) == 0)   // every hole halved on net
}

@Test("An automatic press opens a second bet on the remaining holes")
func automaticPressOpens() throws {
    // Ann wins holes 1 and 2 → Ben is 2 down after hole 2 → press opens for holes 3–9.
    // Ben then wins holes 3, 4 and 5; the rest of the front is halved.
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 4 }
    bScores[1] = 5; bScores[2] = 5
    aScores[3] = 5; aScores[4] = 5; aScores[5] = 5

    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state, config: NassauConfig(unitStake: 10, automaticPressAt: 2)
    )

    // Front nine original bet: Ann 2 up then Ben wins 3 → Ben 1 up → Ben collects 10.
    // Press (holes 3–9): Ben 3 up → Ben collects 10.
    // Back nine: all square → nothing.
    // Total 18: Ben 1 up → Ben collects 10.
    #expect(result.money(for: b) == 30)
    #expect(result.money(for: a) == -30)
    #expect(result.isZeroSum)
    #expect(result.holeExplanations.contains { $0.text.lowercased().contains("press") })
}

@Test("Nassau rejects anything other than two players in Phase 1")
func requiresTwoPlayers() {
    let seats = singles() + [Seat(playerID: UUID(), name: "Cal", courseHandicap: 0)]
    let state = RoundState(log: [], seats: seats, course: .testPar72)
    #expect(throws: NassauEngine.SettleError.requiresTwoPlayers) {
        try NassauEngine.settle(state: state, config: NassauConfig(unitStake: 1, automaticPressAt: nil))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `cannot find 'NassauEngine' in scope`.

- [ ] **Step 3: Write `NassauEngine.swift`**

```swift
import Foundation

public struct NassauConfig: Equatable, Sendable, Codable {
    /// Paid per bet won. A $10 Nassau risks $30 before any press.
    public let unitStake: Decimal
    /// Holes down that trigger an automatic press. `nil` disables presses entirely.
    /// Two is the near-universal convention where presses are played at all.
    public let automaticPressAt: Int?

    public init(unitStake: Decimal, automaticPressAt: Int? = 2) {
        self.unitStake = unitStake
        self.automaticPressAt = automaticPressAt
    }
}

/// Nassau: three match-play bets in one round — front nine, back nine, and the full eighteen.
///
/// The defining feature is the **press**: a side that falls behind opens a fresh bet on the
/// remaining holes, so a blowout front nine still has money live on it. Presses are what make a
/// $10 Nassau routinely settle for $40, and getting them wrong is the fastest way to lose a
/// user's trust.
///
/// Phase 1 is singles only. The 2v2 best-ball variant needs team assignment that the Phase 1b UI
/// does not collect.
public enum NassauEngine: GameDescriptor {
    public static let gameType: GameType = .nassau
    public static let displayName = "Nassau"
    public static let summary = "Three bets in one round: front nine, back nine, and overall. Fall behind and you can press."
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 2...2

    public enum SettleError: Error, Equatable, Sendable {
        case requiresTwoPlayers
    }

    /// One live match-play bet over a range of holes.
    private struct Bet {
        let segment: RoundSegment
        let startHole: Int
        let isPress: Bool
        var holesUp = 0      // positive means the first seat is up
    }

    public static func settle(state: RoundState, config: NassauConfig) throws -> Settlement {
        guard state.seats.count == 2 else { throw SettleError.requiresTwoPlayers }
        let first = state.seats[0], second = state.seats[1]

        var bets: [Bet] = RoundSegment.allCases.map {
            Bet(segment: $0, startHole: $0 == .back ? 10 : 1, isPress: false)
        }
        var explanations: [HoleExplanation] = []

        for hole in state.completedHoles(in: .total) {
            guard let firstNet = state.net(hole: hole, player: first.playerID),
                  let secondNet = state.net(hole: hole, player: second.playerID) else { continue }

            let delta = firstNet == secondNet ? 0 : (firstNet < secondNet ? 1 : -1)

            for index in bets.indices where bets[index].segment.contains(hole: hole)
                && hole >= bets[index].startHole {
                bets[index].holesUp += delta
            }

            let leader = delta > 0 ? first.name : (delta < 0 ? second.name : nil)
            explanations.append(HoleExplanation(
                hole: hole,
                text: leader.map { "Hole \(hole): \($0) wins the hole." }
                    ?? "Hole \(hole): halved."
            ))

            // Presses open *after* the hole is scored, on the remaining holes of that segment.
            guard let trigger = config.automaticPressAt else { continue }
            for bet in bets where !bet.isPress && bet.segment != .total
                && bet.segment.contains(hole: hole) {
                guard abs(bet.holesUp) >= trigger else { continue }
                let nextHole = hole + 1
                guard bet.segment.contains(hole: nextHole) else { continue }
                let alreadyPressed = bets.contains {
                    $0.isPress && $0.segment == bet.segment && $0.startHole == nextHole
                }
                guard !alreadyPressed else { continue }

                bets.append(Bet(segment: bet.segment, startHole: nextHole, isPress: true))
                let trailing = bet.holesUp > 0 ? second.name : first.name
                explanations.append(HoleExplanation(
                    hole: hole,
                    text: "\(trailing) is \(abs(bet.holesUp)) down on the "
                        + "\(bet.segment.displayName) — press opens on hole \(nextHole)."
                ))
            }
        }

        var firstMoney = Decimal(0)
        for bet in bets where bet.holesUp != 0 {
            firstMoney += bet.holesUp > 0 ? config.unitStake : -config.unitStake
        }

        let standings = [
            PlayerStanding(playerID: first.playerID,
                           points: bets.reduce(0) { $0 + $1.holesUp },
                           money: firstMoney),
            PlayerStanding(playerID: second.playerID,
                           points: -bets.reduce(0) { $0 + $1.holesUp },
                           money: -firstMoney)
        ]

        return Settlement(gameType: gameType, standings: standings, holeExplanations: explanations)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: PASS — 39 tests. If the press test fails, check the ordering: a press must open on the hole *after* the trigger, and the original bet keeps running.

- [ ] **Step 5: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add Nassau with automatic presses"
```

---

### Task 9: Wolf

**Files:**
- Create: `Sources/RoundPlayEngine/Games/WolfEngine.swift`
- Test: `Tests/RoundPlayEngineTests/Games/WolfEngineTests.swift`

**Interfaces:**
- Consumes: `RoundState.wolfDeclaration(hole:)`, `Settlement.pointDifferenceMoney`.
- Produces: `WolfEngine.settle(state:config:) -> Settlement`, `WolfConfig(unitStake:partnerWinPoints:loneWolfWinPoints:loneWolfLossPoints:fieldWinPoints:tailHoleRule:)`, `WolfEngine.wolf(forHole:seats:) -> Seat`, `WolfTailHoleRule`.

**Rule:** the Wolf rotates each hole in seat order. The Wolf either takes a partner (two-vs-rest, better-ball net) or goes Lone Wolf against the field. Points are configurable; defaults are partner win 1 each, field win 1 each, Lone Wolf win 4, Lone Wolf loss 1 to each opponent.

**The 18/4 problem:** with four players, 18 holes does not divide evenly. `tailHoleRule` decides holes 17–18: `.rotationContinues` (default, the simplest and most common) or `.stopAfter16`.

- [ ] **Step 1: Write the failing test**

Create `Tests/RoundPlayEngineTests/Games/WolfEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

private let p1 = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
private let p2 = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
private let p3 = UUID(uuidString: "60000000-0000-0000-0000-000000000003")!
private let p4 = UUID(uuidString: "60000000-0000-0000-0000-000000000004")!

private func foursome() -> [Seat] {
    [
        Seat(playerID: p1, name: "One", courseHandicap: 0),
        Seat(playerID: p2, name: "Two", courseHandicap: 0),
        Seat(playerID: p3, name: "Three", courseHandicap: 0),
        Seat(playerID: p4, name: "Four", courseHandicap: 0)
    ]
}

private func makeLog(
    hole: Int,
    declaration: WolfDeclaration,
    wolf: UUID,
    scores: [UUID: Int]
) -> [ScoreEvent] {
    var events = [
        ScoreEvent(id: UUID(), hole: hole, playerID: wolf,
                   payload: .wolfDeclaration(declaration), enteredBy: wolf, sequence: 1)
    ]
    var seq = 1
    for (player, strokes) in scores.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
        seq += 1
        events.append(ScoreEvent(id: UUID(), hole: hole, playerID: player,
                                 payload: .strokes(strokes), enteredBy: wolf, sequence: seq))
    }
    return events
}

@Test("The Wolf rotates through the seats in order")
func wolfRotates() {
    let seats = foursome()
    #expect(WolfEngine.wolf(forHole: 1, seats: seats).playerID == p1)
    #expect(WolfEngine.wolf(forHole: 2, seats: seats).playerID == p2)
    #expect(WolfEngine.wolf(forHole: 4, seats: seats).playerID == p4)
    #expect(WolfEngine.wolf(forHole: 5, seats: seats).playerID == p1)
    #expect(WolfEngine.wolf(forHole: 17, seats: seats).playerID == p1)
}

@Test("Wolf and partner beating the field scores a point each")
func partnershipWins() {
    let log = makeLog(
        hole: 1, declaration: .partner(p2), wolf: p1,
        scores: [p1: 4, p2: 4, p3: 5, p4: 5]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p1) == 1)
    #expect(result.points(for: p2) == 1)
    #expect(result.points(for: p3) == 0)
    #expect(result.points(for: p4) == 0)
    #expect(result.isZeroSum)
}

@Test("The field beating the Wolf pair scores a point each to the field")
func fieldWins() {
    let log = makeLog(
        hole: 1, declaration: .partner(p2), wolf: p1,
        scores: [p1: 5, p2: 5, p3: 4, p4: 6]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p3) == 1)
    #expect(result.points(for: p4) == 1)
    #expect(result.points(for: p1) == 0)
    #expect(result.isZeroSum)
}

@Test("A winning Lone Wolf takes four points")
func loneWolfWins() {
    let log = makeLog(
        hole: 1, declaration: .lone, wolf: p1,
        scores: [p1: 3, p2: 4, p3: 4, p4: 4]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p1) == 4)
    #expect(result.points(for: p2) == 0)
    #expect(result.isZeroSum)
}

@Test("A losing Lone Wolf pays a point to every opponent")
func loneWolfLoses() {
    let log = makeLog(
        hole: 1, declaration: .lone, wolf: p1,
        scores: [p1: 6, p2: 4, p3: 5, p4: 5]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p1) == 0)
    #expect(result.points(for: p2) == 1)
    #expect(result.points(for: p3) == 1)
    #expect(result.points(for: p4) == 1)
    #expect(result.isZeroSum)
}

@Test("A tied hole scores nothing for anyone")
func tiedHoleScoresNothing() {
    let log = makeLog(
        hole: 1, declaration: .partner(p2), wolf: p1,
        scores: [p1: 4, p2: 5, p3: 4, p4: 5]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.standings.allSatisfy { $0.points == 0 })
}

@Test("Holes with no declaration are skipped")
func undeclaredHolesSkipped() {
    var log: [ScoreEvent] = []
    var seq = 0
    for (player, strokes) in [(p1, 4), (p2, 5), (p3, 5), (p4, 5)] {
        seq += 1
        log.append(ScoreEvent(id: UUID(), hole: 1, playerID: player,
                              payload: .strokes(strokes), enteredBy: p1, sequence: seq))
    }
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.standings.allSatisfy { $0.points == 0 })
}

@Test("Better-ball uses the lower net of the pair, not the sum")
func betterBallUsesLowerNet() {
    // Wolf pair: 3 and 7 (better ball 3). Field: 4 and 4 (better ball 4). Wolf pair wins.
    let log = makeLog(
        hole: 1, declaration: .partner(p2), wolf: p1,
        scores: [p1: 3, p2: 7, p3: 4, p4: 4]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p1) == 1)
    #expect(result.points(for: p2) == 1)
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `cannot find 'WolfEngine' in scope`.

- [ ] **Step 3: Write `WolfEngine.swift`**

```swift
import Foundation

/// What happens on holes 17–18 when four players cannot divide 18 evenly.
public enum WolfTailHoleRule: String, Equatable, Sendable, Codable {
    /// Rotation simply continues; seats 1 and 2 get a fifth turn. Simplest, and what most groups do.
    case rotationContinues
    /// Wolf ends after hole 16 and the last two holes score nothing.
    case stopAfter16
}

public struct WolfConfig: Equatable, Sendable, Codable {
    public let unitStake: Decimal
    /// Points to the Wolf and partner when their better ball wins.
    public let partnerWinPoints: Int
    /// Points to each field player when the field wins against a Wolf pair.
    public let fieldWinPoints: Int
    /// Points to a Lone Wolf who beats the whole field.
    public let loneWolfWinPoints: Int
    /// Points to each opponent when a Lone Wolf loses.
    public let loneWolfLossPoints: Int
    public let tailHoleRule: WolfTailHoleRule

    public init(
        unitStake: Decimal,
        partnerWinPoints: Int,
        fieldWinPoints: Int,
        loneWolfWinPoints: Int,
        loneWolfLossPoints: Int,
        tailHoleRule: WolfTailHoleRule
    ) {
        self.unitStake = unitStake
        self.partnerWinPoints = partnerWinPoints
        self.fieldWinPoints = fieldWinPoints
        self.loneWolfWinPoints = loneWolfWinPoints
        self.loneWolfLossPoints = loneWolfLossPoints
        self.tailHoleRule = tailHoleRule
    }

    /// The commonest ruleset. Variants are everywhere, which is exactly why these are config.
    public static func standard(unitStake: Decimal) -> WolfConfig {
        WolfConfig(
            unitStake: unitStake,
            partnerWinPoints: 1,
            fieldWinPoints: 1,
            loneWolfWinPoints: 4,
            loneWolfLossPoints: 1,
            tailHoleRule: .rotationContinues
        )
    }
}

/// Wolf: the tee order rotates, and each hole's Wolf either picks a partner or takes on everyone.
///
/// The only game in the library needing a mid-hole decision, which is why it declares
/// `.partnerChoice` — the scorecard grows a partner picker before scores are entered. A hole with
/// no declaration recorded is skipped rather than guessed at.
public enum WolfEngine: GameDescriptor {
    public static let gameType: GameType = .wolf
    public static let displayName = "Wolf"
    public static let summary = "Take turns being the Wolf. Pick a partner off the tee, or take on all three alone for quadruple points."
    public static let requiredInputs: Set<InputKind> = [.strokes, .partnerChoice]
    public static let playerRange = 3...5

    /// Whose turn it is to be Wolf. Rotates in seat order, wrapping every `seats.count` holes.
    public static func wolf(forHole hole: Int, seats: [Seat]) -> Seat {
        seats[(hole - 1) % seats.count]
    }

    public static func settle(state: RoundState, config: WolfConfig) -> Settlement {
        var points: [UUID: Int] = [:]
        for seat in state.seats { points[seat.playerID] = 0 }
        var explanations: [HoleExplanation] = []

        for hole in state.completedHoles(in: .total) {
            if config.tailHoleRule == .stopAfter16 && hole > 16 { continue }
            guard let declared = state.wolfDeclaration(hole: hole) else { continue }

            let wolfSeat = wolf(forHole: hole, seats: state.seats)
            // Trust the seat rotation over the event's player id — the rotation is the rule.
            guard declared.wolf == wolfSeat.playerID else { continue }

            let wolfTeam: [UUID]
            switch declared.declaration {
            case .partner(let partner): wolfTeam = [wolfSeat.playerID, partner]
            case .lone: wolfTeam = [wolfSeat.playerID]
            }
            let field = state.seats.map(\.playerID).filter { !wolfTeam.contains($0) }

            guard let wolfBall = betterBall(state: state, hole: hole, team: wolfTeam),
                  let fieldBall = betterBall(state: state, hole: hole, team: field) else { continue }

            if wolfBall == fieldBall {
                explanations.append(HoleExplanation(
                    hole: hole, text: "Hole \(hole): halved at net \(wolfBall). No points."
                ))
                continue
            }

            let isLone = wolfTeam.count == 1
            let wolfWon = wolfBall < fieldBall
            let text: String

            if wolfWon {
                let award = isLone ? config.loneWolfWinPoints : config.partnerWinPoints
                for player in wolfTeam { points[player, default: 0] += award }
                text = isLone
                    ? "Hole \(hole): \(wolfSeat.name) went Lone Wolf and won — \(award) points."
                    : "Hole \(hole): \(names(wolfTeam, in: state)) win the hole — \(award) point each."
            } else {
                let award = isLone ? config.loneWolfLossPoints : config.fieldWinPoints
                for player in field { points[player, default: 0] += award }
                text = isLone
                    ? "Hole \(hole): \(wolfSeat.name)'s Lone Wolf failed — \(award) point to each opponent."
                    : "Hole \(hole): \(names(field, in: state)) take the hole — \(award) point each."
            }

            explanations.append(HoleExplanation(hole: hole, text: text))
        }

        let money = Settlement.pointDifferenceMoney(points: points, unitStake: config.unitStake)
        let standings = state.seats.map {
            PlayerStanding(
                playerID: $0.playerID,
                points: points[$0.playerID] ?? 0,
                money: money[$0.playerID] ?? 0
            )
        }

        return Settlement(gameType: gameType, standings: standings, holeExplanations: explanations)
    }

    /// Lowest net on the team — better ball, not combined.
    private static func betterBall(state: RoundState, hole: Int, team: [UUID]) -> Int? {
        team.compactMap { state.net(hole: hole, player: $0) }.min()
    }

    private static func names(_ ids: [UUID], in state: RoundState) -> String {
        ids.compactMap { id in state.seats.first { $0.playerID == id }?.name }
            .joined(separator: " and ")
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: PASS — 47 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add Wolf"
```

---

### Task 10: Game library dispatcher

**Files:**
- Create: `Sources/RoundPlayEngine/GameLibrary.swift`
- Test: `Tests/RoundPlayEngineTests/GameLibraryTests.swift`

**Interfaces:**
- Consumes: all six engines.
- Produces: `GameConfiguration` enum, `GameLibrary.settle(_:state:) throws -> Settlement`, `GameLibrary.metadata(for:) -> GameMetadata`, `GameLibrary.all: [GameMetadata]`, `GameMetadata(gameType:displayName:summary:requiredInputs:playerRange:)`.

This is the single entry point the app uses. It exists so the UI never imports individual engines and never switches on game type itself.

- [ ] **Step 1: Write the failing test**

Create `Tests/RoundPlayEngineTests/GameLibraryTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
private let b = UUID(uuidString: "70000000-0000-0000-0000-000000000002")!

@Test("Library exposes metadata for all six games")
func libraryListsAllGames() {
    #expect(GameLibrary.all.count == 6)
    #expect(Set(GameLibrary.all.map(\.gameType)) == Set(GameType.allCases))
}

@Test("Metadata reports the inputs the scorecard must collect")
func metadataReportsInputs() {
    #expect(GameLibrary.metadata(for: .wolf).requiredInputs.contains(.partnerChoice))
    #expect(GameLibrary.metadata(for: .bingoBangoBongo).requiredInputs == [.holeEvents])
    #expect(GameLibrary.metadata(for: .skins).requiredInputs == [.strokes])
}

@Test("Every game has a non-empty plain-English summary")
func everyGameHasASummary() {
    for metadata in GameLibrary.all {
        #expect(metadata.summary.isEmpty == false, "\(metadata.gameType) has no summary")
        #expect(metadata.displayName.isEmpty == false)
    }
}

@Test("Dispatcher routes a configuration to the right engine")
func dispatcherRoutes() throws {
    let seats = [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 0)
    ]
    let log = [
        ScoreEvent(id: UUID(), hole: 1, playerID: a, payload: .strokes(4), enteredBy: a, sequence: 1),
        ScoreEvent(id: UUID(), hole: 1, playerID: b, payload: .strokes(5), enteredBy: a, sequence: 2)
    ]
    let state = RoundState(log: log, seats: seats, course: .testPar72)

    let result = try GameLibrary.settle(
        .skins(SkinsConfig(unitStake: 5)), state: state
    )
    #expect(result.gameType == .skins)
    #expect(result.money(for: a) == 5)
}

@Test("Player count is validated against the game's supported range")
func playerCountIsValidated() {
    let seats = (1...6).map { Seat(playerID: UUID(), name: "P\($0)", courseHandicap: 0) }
    let state = RoundState(log: [], seats: seats, course: .testPar72)

    #expect(throws: GameLibrary.LibraryError.unsupportedPlayerCount(gameType: .wolf, count: 6)) {
        try GameLibrary.settle(.wolf(.standard(unitStake: 1)), state: state)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `cannot find 'GameLibrary' in scope`.

- [ ] **Step 3: Write `GameLibrary.swift`**

```swift
import Foundation

/// A game plus the settings the group agreed on.
public enum GameConfiguration: Equatable, Sendable, Codable {
    case skins(SkinsConfig)
    case nassau(NassauConfig)
    case stableford(StablefordConfig)
    case nines(NinesConfig)
    case wolf(WolfConfig)
    case bingoBangoBongo(BingoBangoBongoConfig)

    public var gameType: GameType {
        switch self {
        case .skins: .skins
        case .nassau: .nassau
        case .stableford: .stableford
        case .nines: .nines
        case .wolf: .wolf
        case .bingoBangoBongo: .bingoBangoBongo
        }
    }
}

/// Static facts about a game, for the library screen and the scorecard's input rendering.
public struct GameMetadata: Equatable, Sendable, Identifiable {
    public let gameType: GameType
    public let displayName: String
    public let summary: String
    public let requiredInputs: Set<InputKind>
    public let playerRange: ClosedRange<Int>

    public var id: GameType { gameType }

    /// "2–8 players", "3 players", "4 players" — for the library card.
    public var playerCountLabel: String {
        playerRange.lowerBound == playerRange.upperBound
            ? "\(playerRange.lowerBound) players"
            : "\(playerRange.lowerBound)–\(playerRange.upperBound) players"
    }
}

/// The single entry point the app uses to settle any game.
///
/// The UI never imports an engine directly and never switches on `GameType` — adding a seventh
/// game means adding a case here and nothing else changes.
public enum GameLibrary {

    public enum LibraryError: Error, Equatable, Sendable {
        case unsupportedPlayerCount(gameType: GameType, count: Int)
    }

    public static var all: [GameMetadata] {
        GameType.allCases.map(metadata(for:))
    }

    public static func metadata(for gameType: GameType) -> GameMetadata {
        switch gameType {
        case .skins: describe(SkinsEngine.self)
        case .nassau: describe(NassauEngine.self)
        case .stableford: describe(StablefordEngine.self)
        case .nines: describe(NinesEngine.self)
        case .wolf: describe(WolfEngine.self)
        case .bingoBangoBongo: describe(BingoBangoBongoEngine.self)
        }
    }

    public static func settle(
        _ configuration: GameConfiguration,
        state: RoundState
    ) throws -> Settlement {
        let meta = metadata(for: configuration.gameType)
        guard meta.playerRange.contains(state.seats.count) else {
            throw LibraryError.unsupportedPlayerCount(
                gameType: configuration.gameType,
                count: state.seats.count
            )
        }

        switch configuration {
        case .skins(let config):
            return SkinsEngine.settle(state: state, config: config)
        case .nassau(let config):
            return try NassauEngine.settle(state: state, config: config)
        case .stableford(let config):
            return StablefordEngine.settle(state: state, config: config)
        case .nines(let config):
            return try NinesEngine.settle(state: state, config: config)
        case .wolf(let config):
            return WolfEngine.settle(state: state, config: config)
        case .bingoBangoBongo(let config):
            return BingoBangoBongoEngine.settle(state: state, config: config)
        }
    }

    private static func describe<E: GameDescriptor>(_ engine: E.Type) -> GameMetadata {
        GameMetadata(
            gameType: E.gameType,
            displayName: E.displayName,
            summary: E.summary,
            requiredInputs: E.requiredInputs,
            playerRange: E.playerRange
        )
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: PASS — 52 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "feat(engine): add game library dispatcher"
```

---

### Task 11: JSON fixture suite and purity guard

**Files:**
- Create: `Tests/RoundPlayEngineTests/Support/Fixture.swift`
- Create: `Tests/RoundPlayEngineTests/FixtureSuiteTests.swift`
- Create: `Tests/RoundPlayEngineTests/PurityGuardTests.swift`
- Create: `Tests/RoundPlayEngineTests/Fixtures/skins-carryover.json`
- Create: `Tests/RoundPlayEngineTests/Fixtures/nines-ties.json`
- Create: `Tests/RoundPlayEngineTests/Fixtures/wolf-lone-win.json`

**Interfaces:**
- Consumes: `GameLibrary`, `RoundState`, `Settlement`.
- Produces: `EngineFixture` (Codable), `EngineFixture.loadAll() throws -> [EngineFixture]`.

**Why this exists:** the Phase 4 TypeScript port must produce identical money. These JSON files are the contract between the two implementations — the port is *verified*, not reimplemented from memory. Every future game and every bug fix adds a fixture.

- [ ] **Step 1: Write the fixture loader**

Create `Tests/RoundPlayEngineTests/Support/Fixture.swift`:

```swift
import Foundation
import Testing
@testable import RoundPlayEngine

/// A recorded round and the money it must settle to.
///
/// Language-neutral on purpose: the Phase 4 TypeScript engine loads these same files and must
/// produce the same `expectedMoney` to the cent.
struct EngineFixture: Codable {
    struct ExpectedStanding: Codable {
        let playerName: String
        let points: Int
        /// String-encoded to survive JSON without float rounding.
        let money: String
    }

    let name: String
    let engineVersion: String
    let course: Course
    let seats: [Seat]
    let log: [ScoreEvent]
    let configuration: GameConfiguration
    let expected: [ExpectedStanding]

    static func loadAll() throws -> [EngineFixture] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures") ?? []
        let decoder = JSONDecoder()
        return try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try decoder.decode(EngineFixture.self, from: Data(contentsOf: $0)) }
    }
}
```

- [ ] **Step 2: Write the fixture runner test**

Create `Tests/RoundPlayEngineTests/FixtureSuiteTests.swift`:

```swift
import Testing
import Foundation
@testable import RoundPlayEngine

@Test("Fixture suite is present")
func fixturesExist() throws {
    let fixtures = try EngineFixture.loadAll()
    #expect(fixtures.count >= 3, "expected at least three fixtures, found \(fixtures.count)")
}

@Test("Every fixture settles to its recorded money")
func fixturesSettleAsRecorded() throws {
    for fixture in try EngineFixture.loadAll() {
        let state = RoundState(log: fixture.log, seats: fixture.seats, course: fixture.course)
        let result = try GameLibrary.settle(fixture.configuration, state: state)

        #expect(result.isZeroSum, "\(fixture.name) is not zero-sum")

        for expected in fixture.expected {
            guard let seat = fixture.seats.first(where: { $0.name == expected.playerName }) else {
                Issue.record("\(fixture.name): no seat named \(expected.playerName)")
                continue
            }
            #expect(
                result.points(for: seat.playerID) == expected.points,
                "\(fixture.name): \(expected.playerName) points"
            )
            #expect(
                result.money(for: seat.playerID) == Decimal(string: expected.money),
                "\(fixture.name): \(expected.playerName) money"
            )
        }
    }
}

@Test("Fixtures declare the engine version they were recorded against")
func fixturesDeclareVersion() throws {
    for fixture in try EngineFixture.loadAll() {
        #expect(
            fixture.engineVersion == RoundPlayEngineVersion.current,
            "\(fixture.name) was recorded against \(fixture.engineVersion) but the engine is now "
                + "\(RoundPlayEngineVersion.current). Re-record it deliberately, or the rule change was a regression."
        )
    }
}
```

- [ ] **Step 3: Generate the three fixture files**

Write a throwaway generator so the JSON matches the encoders exactly rather than being hand-typed. Create `Tests/RoundPlayEngineTests/Support/FixtureRecorder.swift`:

```swift
import Foundation
import Testing
@testable import RoundPlayEngine

/// Run with `swift test --filter recordFixtures` to (re)write the JSON fixtures on disk.
///
/// Disabled by default: it writes into the source tree, which a normal test run must not do.
/// Enable deliberately when a rule legitimately changes, then review the JSON diff before committing —
/// that diff *is* the record of what money moved.
@Test(.disabled("Run manually to re-record fixtures"))
func recordFixtures() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // Support/
        .deletingLastPathComponent()          // RoundPlayEngineTests/
        .appendingPathComponent("Fixtures")

    for fixture in FixtureCatalog.all {
        let data = try encoder.encode(fixture)
        try data.write(to: directory.appendingPathComponent("\(fixture.name).json"))
    }
}
```

Create `Tests/RoundPlayEngineTests/Support/FixtureCatalog.swift` defining the three scenarios. Each reuses the engine test helpers, and `expected` values are the ones already asserted in Tasks 4, 6, and 9:

```swift
import Foundation
@testable import RoundPlayEngine

/// The canonical fixtures. Add one for every rule that has ever been argued about.
enum FixtureCatalog {
    static let ann = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    static let ben = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
    static let cal = UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!
    static let dee = UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!

    static var all: [EngineFixture] { [skinsCarryover, ninesTies, wolfLoneWin] }

    private static func threeSeats() -> [Seat] {
        [
            Seat(playerID: ann, name: "Ann", courseHandicap: 0),
            Seat(playerID: ben, name: "Ben", courseHandicap: 0),
            Seat(playerID: cal, name: "Cal", courseHandicap: 0)
        ]
    }

    private static func strokes(
        _ entries: [(hole: Int, player: UUID, strokes: Int)]
    ) -> [ScoreEvent] {
        entries.enumerated().map { index, entry in
            ScoreEvent(
                id: UUID(uuidString: String(format: "B0000000-0000-0000-0000-%012d", index))!,
                hole: entry.hole, playerID: entry.player,
                payload: .strokes(entry.strokes), enteredBy: ann, sequence: index + 1
            )
        }
    }

    /// Hole 1 ties and carries; Ann wins two skins on hole 2 at $5 a skin from two opponents.
    static var skinsCarryover: EngineFixture {
        EngineFixture(
            name: "skins-carryover",
            engineVersion: RoundPlayEngineVersion.current,
            course: .testPar72,
            seats: threeSeats(),
            log: strokes([
                (1, ann, 4), (1, ben, 4), (1, cal, 5),
                (2, ann, 3), (2, ben, 5), (2, cal, 5)
            ]),
            configuration: .skins(SkinsConfig(unitStake: 5)),
            expected: [
                .init(playerName: "Ann", points: 2, money: "20"),
                .init(playerName: "Ben", points: 0, money: "-10"),
                .init(playerName: "Cal", points: 0, money: "-10")
            ]
        )
    }

    /// Every Nines tie shape in one round: clean, all-tied, tied-low, tied-high.
    static var ninesTies: EngineFixture {
        EngineFixture(
            name: "nines-ties",
            engineVersion: RoundPlayEngineVersion.current,
            course: .testPar72,
            seats: threeSeats(),
            log: strokes([
                (1, ann, 3), (1, ben, 4), (1, cal, 5),   // 5 / 3 / 1
                (2, ann, 4), (2, ben, 4), (2, cal, 4),   // 3 / 3 / 3
                (3, ann, 3), (3, ben, 3), (3, cal, 5),   // 4 / 4 / 1
                (4, ann, 3), (4, ben, 5), (4, cal, 5)    // 5 / 2 / 2
            ]),
            configuration: .nines(NinesConfig(unitStake: 1)),
            expected: [
                // Ann 17, Ben 12, Cal 7 → differences at $1: Ann +15, Ben 0, Cal −15.
                .init(playerName: "Ann", points: 17, money: "15"),
                .init(playerName: "Ben", points: 12, money: "0"),
                .init(playerName: "Cal", points: 7, money: "-15")
            ]
        )
    }

    /// A Lone Wolf that comes off — the biggest single-hole swing in the library.
    static var wolfLoneWin: EngineFixture {
        let seats = [
            Seat(playerID: ann, name: "Ann", courseHandicap: 0),
            Seat(playerID: ben, name: "Ben", courseHandicap: 0),
            Seat(playerID: cal, name: "Cal", courseHandicap: 0),
            Seat(playerID: dee, name: "Dee", courseHandicap: 0)
        ]
        var log = strokes([(1, ann, 3), (1, ben, 4), (1, cal, 4), (1, dee, 4)])
        log.insert(
            ScoreEvent(
                id: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
                hole: 1, playerID: ann, payload: .wolfDeclaration(.lone),
                enteredBy: ann, sequence: 0
            ),
            at: 0
        )
        return EngineFixture(
            name: "wolf-lone-win",
            engineVersion: RoundPlayEngineVersion.current,
            course: .testPar72,
            seats: seats,
            log: log,
            configuration: .wolf(.standard(unitStake: 1)),
            expected: [
                // Ann 4 pts, everyone else 0 → Ann +12, each opponent −4.
                .init(playerName: "Ann", points: 4, money: "12"),
                .init(playerName: "Ben", points: 0, money: "-4"),
                .init(playerName: "Cal", points: 0, money: "-4"),
                .init(playerName: "Dee", points: 0, money: "-4")
            ]
        )
    }
}
```

Record them:

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine
swift test --filter recordFixtures --skip-testing-library-disabled 2>/dev/null || \
  swift test --filter recordFixtures
```

If the disabled-test filter will not run it, temporarily remove the `.disabled(...)` trait, run, and restore it. Verify three JSON files now exist in `Tests/RoundPlayEngineTests/Fixtures/`.

- [ ] **Step 4: Write the purity guard test**

Create `Tests/RoundPlayEngineTests/PurityGuardTests.swift`:

```swift
import Testing
import Foundation

/// The engine's whole value rests on being deterministic. A stray `import SwiftUI` or a `Date()`
/// inside a settle function would make a settled round recompute differently later, which is the
/// one failure mode that cannot be recovered from — the money already changed hands.
@Test("Engine sources import nothing but Foundation")
func engineImportsOnlyFoundation() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/RoundPlayEngine")

    let banned = ["SwiftUI", "UIKit", "SwiftData", "Combine", "Network", "CloudKit"]
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" } ?? []

    #expect(files.isEmpty == false, "found no engine sources to check")

    for file in files {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for module in banned {
            #expect(
                contents.contains("import \(module)") == false,
                "\(file.lastPathComponent) imports \(module) — the engine must stay pure"
            )
        }
    }
}

@Test("Engine sources contain no non-deterministic calls")
func engineIsDeterministic() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/RoundPlayEngine")

    let banned = ["Date()", "UUID()", ".random", "arc4random"]
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" } ?? []

    for file in files {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for call in banned {
            #expect(
                contents.contains(call) == false,
                "\(file.lastPathComponent) contains \(call) — settlement must be reproducible"
            )
        }
    }
}
```

- [ ] **Step 5: Run the full suite**

```bash
cd /Users/nik/workplace/RoundPlay/Packages/RoundPlayEngine && swift test
```

Expected: PASS — 57 tests. If the purity guard fails, the offending import or call is a real defect; remove it rather than relaxing the guard.

- [ ] **Step 6: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add Packages/RoundPlayEngine
git commit -m "test(engine): add JSON fixture suite and purity guards"
```

---

## Phase 1a exit criteria

- [ ] `cd Packages/RoundPlayEngine && swift test` passes with 57+ tests.
- [ ] All six games settle zero-sum in every test.
- [ ] Three JSON fixtures exist and are committed.
- [ ] Purity guards pass — no forbidden imports, no non-deterministic calls.
- [ ] `GameLibrary.all.count == 6`.

## Known scope limits, recorded deliberately

These are **decisions, not omissions**. Each is a case where guessing would produce
silently-wrong money:

- **Nassau is singles only.** 2v2 best ball needs team assignment the Phase 1b UI does not collect.
- **Plus handicaps clamp to scratch.** The convention for giving strokes back is not uniform; needs a real plus-handicap tester.
- **Unclaimed skins expire unpaid.** Groups that split the leftover do it in cash.
- **Wolf's blind/"pig" triple-value declaration is not modelled.** Add it as a `WolfDeclaration` case with its own fixture when someone asks.

Phase 1b (`2026-08-08-roundplay-phase-1b-app.md`) builds the app on top of this package.
