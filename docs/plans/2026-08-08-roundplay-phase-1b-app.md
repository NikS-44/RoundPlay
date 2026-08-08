# RoundPlay Phase 1b — Playable App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single-device app where one person keeps score for a group start to finish and gets correct money — course entry, player roster, round creation, the hole screen, and a live dashboard with a greyed-out Settle Up.

**Architecture:** SwiftData holds the append-only event log locally; `RoundPlayEngine` computes every score and every dollar. The app never implements a scoring rule — it collects input, persists events, and renders `Settlement`. No backend in this phase.

**Tech Stack:** Swift 6.2, SwiftUI + Observation, SwiftData, `RoundPlayEngine`.

## Execution Mode

Run this plan's tasks continuously, start to finish, without pausing for step-by-step
approval or asking "should I proceed?" between tasks. Run each verification command as
specified and move on when it passes. **Only stop and ask the user when a decision is
genuinely controversial or ambiguous** — a product/scope/rules judgment call this plan
doesn't already resolve, not an implementation detail. When you do have a reasonable
recommendation, state it briefly and keep going rather than blocking on confirmation.
This applies to every plan in this project, in this session and any future one.

## Global Constraints

- **Do not run `xcodebuild`.** Engine changes are verified with `swift test`; app changes are verified by the user in Xcode.
- **Verification for this phase is SwiftUI Previews plus a user run-through**, not automated tests. App-target unit tests need `xcodebuild` and are deferred. Every view therefore ships with `#Preview` blocks for **both light and dark** — those previews *are* the test surface, so they must use realistic data, never empty states.
- **The app must not contain a scoring rule.** No arithmetic on strokes, no par comparisons, no money math outside `RoundPlayEngine`. If a view needs a number, it comes from `Settlement` or `RoundState`.
- Any logic that can live in the engine package **should**, because that is the only thing testable under this constraint.
- **Money renders from `Decimal` via `NumberFormatter`/`.formatted(.currency(code:))`** — never string interpolation of a raw value.
- Every view uses `RoundPlayColors` tokens. No raw `.red`/`.green`.
- Tap targets on the hole screen are **at least 44×44 pt** and support Dynamic Type. The target user is 70, outdoors, in direct sun.
- Prerequisites: Phase 0 complete, Phase 1a complete (`GameLibrary` exists and `swift test` passes).
- After editing any file layout, re-run `xcodegen generate`.

---

### Task 1: SwiftData schema and the engine bridge

**Files:**
- Create: `RoundPlay/Core/RoundPlaySchema.swift`
- Create: `RoundPlay/Models/PlayerRecord.swift`
- Create: `RoundPlay/Models/CourseRecord.swift`
- Create: `RoundPlay/Models/RoundRecord.swift`
- Create: `RoundPlay/Models/ScoreEventRecord.swift`
- Create: `RoundPlay/Services/EngineBridge.swift`
- Modify: `RoundPlay/RoundPlayApp.swift`

**Interfaces:**
- Consumes: `RoundPlayEngine` types (`Course`, `Hole`, `Seat`, `ScoreEvent`, `GameConfiguration`).
- Produces: `RoundPlaySchema.makeContainer()`, `@Model` classes `PlayerRecord`, `CourseRecord`, `RoundRecord`, `SeatRecord`, `GameInstanceRecord`, `ScoreEventRecord`; `EngineBridge.roundState(for:) -> RoundState`, `EngineBridge.settlements(for:) throws -> [Settlement]`, `EngineBridge.appendStrokes(...)`, `EngineBridge.appendWolfDeclaration(...)`, `EngineBridge.appendHoleEvent(...)`.

> **Schema note:** unlike UpKeepr, the store filename does **not** encode a version. Phase 2 replaces this store with server-backed state, so a migration plan here would be wasted work. Every non-optional property still gets a default value, because Phase 2's sync layer will want CloudKit-shaped records even though CloudKit itself is not used.

- [ ] **Step 1: Write `PlayerRecord.swift`**

```swift
import Foundation
import SwiftData

/// Someone you play with — your roster, and the "recurring companions" feature.
///
/// Sorted by `lastPlayedAt` so adding the regular Saturday group to a new round is four taps.
/// `linkedAccountID` is unused in Phase 1 and exists so Phase 2 can bind a roster entry to a real
/// signed-in human without a migration.
@Model
final class PlayerRecord {
    var id: UUID = UUID()
    var name: String = ""
    /// Self-reported. `nil` means they play off scratch or have not told us.
    var handicapIndex: Double?
    var linkedAccountID: UUID?
    var lastPlayedAt: Date?
    var playCount: Int = 0
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, handicapIndex: Double? = nil) {
        self.id = id
        self.name = name
        self.handicapIndex = handicapIndex
    }

    /// Course handicap, rounded to whole strokes.
    ///
    /// The real USGA formula factors slope and course rating, which Phase 1 does not collect.
    /// Using the index directly is the standard casual-play approximation and is what a group
    /// agreeing strokes on the first tee would do anyway.
    var courseHandicap: Int {
        Int((handicapIndex ?? 0).rounded())
    }
}
```

- [ ] **Step 2: Write `CourseRecord.swift`**

```swift
import Foundation
import SwiftData
import RoundPlayEngine

/// A course as entered by whoever played it first.
///
/// Pars and stroke indexes are stored as flat 18-element arrays rather than a child model: they
/// are always read together, never queried individually, and a relationship would buy nothing.
@Model
final class CourseRecord {
    var id: UUID = UUID()
    var name: String = ""
    var pars: [Int] = []
    var strokeIndexes: [Int] = []
    var createdAt: Date = Date()
    var lastPlayedAt: Date?

    init(id: UUID = UUID(), name: String, pars: [Int], strokeIndexes: [Int]) {
        self.id = id
        self.name = name
        self.pars = pars
        self.strokeIndexes = strokeIndexes
    }

    /// Engine value type. Returns `nil` when the record is incomplete or invalid — callers must
    /// treat that as "this course cannot be played" rather than substituting defaults.
    var engineCourse: Course? {
        guard pars.count == 18, strokeIndexes.count == 18 else { return nil }
        let holes = (0..<18).map {
            Hole(number: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0])
        }
        return try? Course.validated(id: id, name: name, holes: holes)
    }

    var totalPar: Int { pars.reduce(0, +) }
}
```

- [ ] **Step 3: Write `RoundRecord.swift`**

```swift
import Foundation
import SwiftData
import RoundPlayEngine

/// A group's round: a course, the seats, and the games being played.
@Model
final class RoundRecord {
    var id: UUID = UUID()
    var courseID: UUID = UUID()
    var courseName: String = ""
    var startedAt: Date = Date()
    var completedAt: Date?
    /// Monotonic counter for `ScoreEventRecord.sequence`. Phase 2 hands this to the server.
    var nextSequence: Int = 1

    @Relationship(deleteRule: .cascade) var seats: [SeatRecord]? = []
    @Relationship(deleteRule: .cascade) var games: [GameInstanceRecord]? = []
    @Relationship(deleteRule: .cascade) var events: [ScoreEventRecord]? = []

    init(id: UUID = UUID(), courseID: UUID, courseName: String) {
        self.id = id
        self.courseID = courseID
        self.courseName = courseName
    }

    var orderedSeats: [SeatRecord] {
        (seats ?? []).sorted { $0.position < $1.position }
    }

    var isComplete: Bool { completedAt != nil }
}

/// A player's place in a round.
///
/// `name` and `courseHandicap` are **copied** from `PlayerRecord` rather than referenced, so a
/// finished round always recomputes to the same money even after the player's handicap changes.
@Model
final class SeatRecord {
    var id: UUID = UUID()
    var playerID: UUID = UUID()
    var name: String = ""
    var courseHandicap: Int = 0
    /// Tee order. Drives the Wolf rotation, so it must be stable.
    var position: Int = 0

    init(id: UUID = UUID(), playerID: UUID, name: String, courseHandicap: Int, position: Int) {
        self.id = id
        self.playerID = playerID
        self.name = name
        self.courseHandicap = courseHandicap
        self.position = position
    }

    var engineSeat: Seat {
        Seat(playerID: playerID, name: name, courseHandicap: courseHandicap)
    }
}

/// One game running in a round. A round commonly runs two — Skins plus a Nassau.
@Model
final class GameInstanceRecord {
    var id: UUID = UUID()
    var gameTypeRaw: String = ""
    /// `GameConfiguration` encoded as JSON. Stored opaquely so adding a game or a config field
    /// never touches the schema.
    var configurationData: Data = Data()

    init(id: UUID = UUID(), configuration: GameConfiguration) throws {
        self.id = id
        self.gameTypeRaw = configuration.gameType.rawValue
        self.configurationData = try JSONEncoder().encode(configuration)
    }

    var gameType: GameType? { GameType(rawValue: gameTypeRaw) }

    var configuration: GameConfiguration? {
        try? JSONDecoder().decode(GameConfiguration.self, from: configurationData)
    }
}
```

- [ ] **Step 4: Write `ScoreEventRecord.swift`**

```swift
import Foundation
import SwiftData
import RoundPlayEngine

/// One append-only entry in a round's log.
///
/// **Never update or delete one of these.** A correction appends a new record with a higher
/// `sequence`; the earlier one is what makes the audit view possible and what Phase 2's offline
/// sync replays. Mutating in place would destroy both.
@Model
final class ScoreEventRecord {
    var id: UUID = UUID()
    var hole: Int = 0
    var playerID: UUID = UUID()
    /// `ScoreEventPayload` encoded as JSON — the payload is an enum with associated values.
    var payloadData: Data = Data()
    var enteredBy: UUID = UUID()
    var enteredByName: String = ""
    var sequence: Int = 0
    var recordedAt: Date = Date()

    init(
        id: UUID = UUID(),
        hole: Int,
        playerID: UUID,
        payload: ScoreEventPayload,
        enteredBy: UUID,
        enteredByName: String,
        sequence: Int
    ) throws {
        self.id = id
        self.hole = hole
        self.playerID = playerID
        self.payloadData = try JSONEncoder().encode(payload)
        self.enteredBy = enteredBy
        self.enteredByName = enteredByName
        self.sequence = sequence
    }

    var payload: ScoreEventPayload? {
        try? JSONDecoder().decode(ScoreEventPayload.self, from: payloadData)
    }

    var engineEvent: ScoreEvent? {
        guard let payload else { return nil }
        return ScoreEvent(
            id: id, hole: hole, playerID: playerID,
            payload: payload, enteredBy: enteredBy, sequence: sequence
        )
    }
}
```

- [ ] **Step 5: Write `RoundPlaySchema.swift`**

```swift
import Foundation
import SwiftData
import os

private let schemaLogger = Logger(subsystem: "app.roundplay", category: "Schema")

/// SwiftData container setup.
///
/// Phase 1 is local-only: no CloudKit, no sync. Phase 2 makes the server authoritative and
/// demotes this store to a cache plus an outbox, so there is deliberately no migration plan or
/// versioned store filename here — that work would be thrown away.
enum RoundPlaySchema {
    static var allModelTypes: [any PersistentModel.Type] {
        [
            PlayerRecord.self,
            CourseRecord.self,
            RoundRecord.self,
            SeatRecord.self,
            GameInstanceRecord.self,
            ScoreEventRecord.self
        ]
    }

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(allModelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            schemaLogger.error("Failed to create ModelContainer: \(error.localizedDescription)")
            // An in-memory fallback keeps the app usable rather than crashing on launch.
            // Phase 2 replaces this with a real recovery path once the server holds the truth.
            return try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
    }

    static let appContainer: ModelContainer = makeContainer()
}
```

- [ ] **Step 6: Write `EngineBridge.swift`**

```swift
import Foundation
import SwiftData
import RoundPlayEngine

/// The only seam between SwiftData and the scoring engine.
///
/// Views call this and never assemble `RoundState` themselves, so the record→value-type mapping
/// is defined exactly once.
enum EngineBridge {

    enum BridgeError: Error {
        case courseUnavailable
    }

    static func roundState(for round: RoundRecord, course: Course) -> RoundState {
        RoundState(
            log: (round.events ?? []).compactMap(\.engineEvent),
            seats: round.orderedSeats.map(\.engineSeat),
            course: course
        )
    }

    /// Settles every game in the round. A game whose configuration fails to decode, or whose
    /// player count no longer fits, is skipped rather than crashing the dashboard.
    static func settlements(for round: RoundRecord, course: Course) -> [Settlement] {
        let state = roundState(for: round, course: course)
        return (round.games ?? []).compactMap { game in
            guard let configuration = game.configuration else { return nil }
            return try? GameLibrary.settle(configuration, state: state)
        }
    }

    // MARK: - Appending events

    @discardableResult
    static func append(
        payload: ScoreEventPayload,
        hole: Int,
        playerID: UUID,
        to round: RoundRecord,
        enteredBy: UUID,
        enteredByName: String,
        in context: ModelContext
    ) throws -> ScoreEventRecord {
        let record = try ScoreEventRecord(
            hole: hole,
            playerID: playerID,
            payload: payload,
            enteredBy: enteredBy,
            enteredByName: enteredByName,
            sequence: round.nextSequence
        )
        round.nextSequence += 1
        round.events = (round.events ?? []) + [record]
        context.insert(record)
        try context.save()
        return record
    }

    static func appendStrokes(
        _ strokes: Int, hole: Int, playerID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .strokes(strokes), hole: hole, playerID: playerID,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    static func appendWolfDeclaration(
        _ declaration: WolfDeclaration, hole: Int, wolfID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .wolfDeclaration(declaration), hole: hole, playerID: wolfID,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    static func appendHoleEvent(
        _ kind: HoleEventKind, hole: Int, playerID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .holeEvent(kind), hole: hole, playerID: playerID,
                   to: round, enteredBy: enteredBy,
                   enteredByName: enteredByName, in: context)
    }
}
```

- [ ] **Step 7: Wire the container into the app**

Replace the body of `RoundPlay/RoundPlayApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct RoundPlayApp: App {
    @UIApplicationDelegateAdaptor(RoundPlayAppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = RoundPlaySchema.appContainer

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

- [ ] **Step 8: Regenerate and verify the engine still passes**

```bash
cd /Users/nik/workplace/RoundPlay && xcodegen generate
cd Packages/RoundPlayEngine && swift test
```

Expected: project regenerates; engine tests still PASS.

- [ ] **Step 9: Commit**

```bash
cd /Users/nik/workplace/RoundPlay
git add RoundPlay project.yml
git commit -m "feat: add SwiftData schema and engine bridge"
```

---

### Task 2: Course entry

**Files:**
- Create: `RoundPlay/Features/Courses/CourseListView.swift`
- Create: `RoundPlay/Features/Courses/CourseEntryView.swift`
- Create: `RoundPlay/Features/Courses/CourseEntryModel.swift`

**Interfaces:**
- Consumes: `CourseRecord`, `RoundPlayColors`, `RoundPlayList`.
- Produces: `CourseListView(onSelect:)`, `CourseEntryView(onSave:)`, `@Observable CourseEntryModel` with `pars: [Int]`, `strokeIndexes: [Int]`, `validationMessage: String?`, `isValid: Bool`.

**The interaction that matters:** entering 18 pars and 18 stroke indexes is the one genuinely tedious screen in the app, done once per course by one person, off the physical scorecard in their hand. Optimize for *that* posture: a single scrolling grid, keyboard never needed, sensible defaults pre-filled.

- [ ] **Step 1: Write `CourseEntryModel.swift`**

```swift
import Foundation
import Observation
import RoundPlayEngine

/// Editing state for a course being entered.
///
/// Pre-filled with a conventional par-72 layout and the standard odd-front/even-back stroke index
/// pattern, because most courses are close to it — the user is correcting a few holes rather than
/// entering 36 numbers from scratch.
@Observable
final class CourseEntryModel {
    var name: String = ""
    var pars: [Int]
    var strokeIndexes: [Int]

    init() {
        pars = [4, 5, 3, 4, 4, 3, 5, 4, 4,
                4, 3, 5, 4, 4, 3, 5, 4, 4]
        strokeIndexes = [1, 11, 17, 3, 7, 15, 13, 5, 9,
                         2, 16, 12, 4, 8, 18, 14, 6, 10]
    }

    var totalPar: Int { pars.reduce(0, +) }

    /// Human-readable reason the course cannot be saved, or `nil` when it is valid.
    ///
    /// Duplicate stroke indexes are the error users actually make — transposing two holes while
    /// copying — so it names the offending number rather than saying "invalid".
    var validationMessage: String? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Give the course a name."
        }
        let counts = Dictionary(grouping: strokeIndexes, by: { $0 }).mapValues(\.count)
        if let duplicate = counts.first(where: { $0.value > 1 })?.key {
            return "Stroke index \(duplicate) is used more than once. Each hole needs its own 1–18."
        }
        if Set(strokeIndexes) != Set(1...18) {
            let missing = Set(1...18).subtracting(strokeIndexes).sorted()
            return "Missing stroke index \(missing.map(String.init).joined(separator: ", "))."
        }
        return nil
    }

    var isValid: Bool { validationMessage == nil }
}
```

- [ ] **Step 2: Write `CourseEntryView.swift`**

```swift
import SwiftUI
import SwiftData

/// One-time course setup: 18 pars and 18 stroke indexes, copied off the scorecard.
struct CourseEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model = CourseEntryModel()
    let onSave: (CourseRecord) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Course name", text: $model.name)
                    .textInputAutocapitalization(.words)
            } footer: {
                Text("Total par \(model.totalPar)")
            }

            Section("Holes") {
                ForEach(0..<18, id: \.self) { index in
                    HoleEntryRow(
                        holeNumber: index + 1,
                        par: $model.pars[index],
                        strokeIndex: $model.strokeIndexes[index]
                    )
                }
            }

            if let message = model.validationMessage {
                Section {
                    Text(message).foregroundStyle(RoundPlayColors.destructive)
                }
            }
        }
        .navigationTitle("Add Course")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!model.isValid)
            }
        }
    }

    private func save() {
        let record = CourseRecord(
            name: model.name.trimmingCharacters(in: .whitespaces),
            pars: model.pars,
            strokeIndexes: model.strokeIndexes
        )
        modelContext.insert(record)
        try? modelContext.save()
        onSave(record)
        dismiss()
    }
}

/// One hole's par and stroke index, both as steppers — no keyboard, no numeric input errors.
private struct HoleEntryRow: View {
    let holeNumber: Int
    @Binding var par: Int
    @Binding var strokeIndex: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(holeNumber)")
                .font(.headline.monospacedDigit())
                .frame(width: 28, alignment: .leading)

            Picker("Par", selection: $par) {
                ForEach(3...6, id: \.self) { Text("Par \($0)").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Spacer()

            Picker("Stroke index", selection: $strokeIndex) {
                ForEach(1...18, id: \.self) { Text("SI \($0)").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hole \(holeNumber), par \(par), stroke index \(strokeIndex)")
    }
}

#Preview("Light") {
    NavigationStack { CourseEntryView { _ in } }
        .modelContainer(RoundPlaySchema.makeContainer(inMemory: true))
}

#Preview("Dark") {
    NavigationStack { CourseEntryView { _ in } }
        .modelContainer(RoundPlaySchema.makeContainer(inMemory: true))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 3: Write `CourseListView.swift`**

```swift
import SwiftUI
import SwiftData

/// Pick a course, or add one. Recents first — most groups replay the same two or three.
struct CourseListView: View {
    @Query(sort: [SortDescriptor(\CourseRecord.lastPlayedAt, order: .reverse),
                  SortDescriptor(\CourseRecord.name)])
    private var courses: [CourseRecord]

    @State private var isAddingCourse = false
    let onSelect: (CourseRecord) -> Void

    var body: some View {
        RoundPlayList.plain {
            if courses.isEmpty {
                ContentUnavailableView(
                    "No courses yet",
                    systemImage: "flag",
                    description: Text("Add a course from the scorecard in your hand. Everyone who plays there after you gets it automatically.")
                )
            }

            ForEach(courses) { course in
                Button {
                    onSelect(course)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.body)
                            Text("Par \(course.totalPar)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(RoundPlayRowButtonStyle())
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Course")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isAddingCourse = true }
            }
        }
        .sheet(isPresented: $isAddingCourse) {
            NavigationStack {
                CourseEntryView { course in onSelect(course) }
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { CourseListView { _ in } }
        .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { CourseListView { _ in } }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 4: Create preview data**

Create `RoundPlay/Support/PreviewData.swift`. Previews are the only verification surface in this phase, so this must produce a realistic round, not an empty one.

```swift
import Foundation
import SwiftData
import RoundPlayEngine

/// Realistic sample data for previews.
///
/// Previews are this phase's test surface, so this builds a *partially played* round — the state
/// most screens are actually rendered in — rather than an empty or completed one.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = RoundPlaySchema.makeContainer(inMemory: true)
        let context = container.mainContext

        let course = CourseRecord(
            name: "Pebble Creek",
            pars: [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4],
            strokeIndexes: [1, 11, 17, 3, 7, 15, 13, 5, 9, 2, 16, 12, 4, 8, 18, 14, 6, 10]
        )
        course.lastPlayedAt = Date()
        context.insert(course)

        let players = [
            ("Ann", 8.0), ("Ben", 14.0), ("Cal", 22.0), ("Dee", 3.0)
        ].map { PlayerRecord(name: $0.0, handicapIndex: $0.1) }
        players.forEach {
            $0.lastPlayedAt = Date()
            $0.playCount = 6
            context.insert($0)
        }

        let round = RoundRecord(courseID: course.id, courseName: course.name)
        round.seats = players.enumerated().map { index, player in
            SeatRecord(playerID: player.id, name: player.name,
                       courseHandicap: player.courseHandicap, position: index)
        }
        round.games = [try? GameInstanceRecord(configuration: .skins(SkinsConfig(unitStake: 5)))]
            .compactMap { $0 }
        context.insert(round)

        // Five holes played, so dashboards and standings have something to show.
        let scores: [[Int]] = [
            [4, 5, 6, 4], [5, 6, 7, 5], [3, 4, 4, 3], [4, 4, 6, 4], [5, 5, 5, 4]
        ]
        for (holeIndex, holeScores) in scores.enumerated() {
            for (seatIndex, strokes) in holeScores.enumerated() {
                let seat = round.orderedSeats[seatIndex]
                try? EngineBridge.appendStrokes(
                    strokes, hole: holeIndex + 1, playerID: seat.playerID, to: round,
                    enteredBy: round.orderedSeats[0].playerID,
                    enteredByName: round.orderedSeats[0].name,
                    in: context
                )
            }
        }

        try? context.save()
        return container
    }()

    static var sampleRound: RoundRecord {
        (try? container.mainContext.fetch(FetchDescriptor<RoundRecord>()))?.first
            ?? RoundRecord(courseID: UUID(), courseName: "Preview")
    }
}
```

- [ ] **Step 5: Regenerate and commit**

```bash
cd /Users/nik/workplace/RoundPlay && xcodegen generate
git add RoundPlay
git commit -m "feat: add course entry and course list"
```

**User verification:** open the `CourseEntryView` preview in both appearances. Confirm the steppers are reachable one-handed, the duplicate-stroke-index message names the offending number, and Save stays disabled until valid.

---

### Task 3: Player roster

**Files:**
- Create: `RoundPlay/Features/Players/PlayerListView.swift`
- Create: `RoundPlay/Features/Players/PlayerEditSheet.swift`
- Modify: `RoundPlay/ContentView.swift`

**Interfaces:**
- Consumes: `PlayerRecord`, `RoundPlayColors`.
- Produces: `PlayerListView()`, `PlayerPickerView(selection:)`, `PlayerEditSheet(player:onSave:)`.

- [ ] **Step 1: Write `PlayerEditSheet.swift`**

```swift
import SwiftUI
import SwiftData

/// Add or edit someone in your roster.
///
/// A name is **required** — the whole point of the roster is that scores belong to Bob, not to
/// "Player 3". Handicap is optional because plenty of casual golfers do not have one, and
/// demanding it would be a wall in front of the first round.
struct PlayerEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let player: PlayerRecord?
    let onSave: (PlayerRecord) -> Void

    @State private var name: String = ""
    @State private var handicapText: String = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            Section {
                TextField("Handicap index", text: $handicapText)
                    .keyboardType(.decimalPad)
            } header: {
                Text("Handicap")
            } footer: {
                Text("Optional. Leave blank to play off scratch. Strokes are given on the hardest holes.")
            }
        }
        .navigationTitle(player == nil ? "New Player" : "Edit Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(trimmedName.isEmpty)
            }
        }
        .onAppear {
            name = player?.name ?? ""
            handicapText = player?.handicapIndex.map { String($0) } ?? ""
        }
    }

    private func save() {
        let handicap = Double(handicapText.trimmingCharacters(in: .whitespaces))
        let record: PlayerRecord
        if let player {
            player.name = trimmedName
            player.handicapIndex = handicap
            record = player
        } else {
            record = PlayerRecord(name: trimmedName, handicapIndex: handicap)
            modelContext.insert(record)
        }
        try? modelContext.save()
        onSave(record)
        dismiss()
    }
}

#Preview("Light") {
    NavigationStack { PlayerEditSheet(player: nil) { _ in } }
        .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { PlayerEditSheet(player: nil) { _ in } }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Write `PlayerListView.swift`**

```swift
import SwiftUI
import SwiftData

/// Your roster of playing companions, most recent first.
struct PlayerListView: View {
    @Query(sort: [SortDescriptor(\PlayerRecord.lastPlayedAt, order: .reverse),
                  SortDescriptor(\PlayerRecord.name)])
    private var players: [PlayerRecord]

    @Environment(\.modelContext) private var modelContext
    @State private var editingPlayer: PlayerRecord?
    @State private var isAddingPlayer = false

    var body: some View {
        RoundPlayList.plain {
            if players.isEmpty {
                ContentUnavailableView(
                    "No players yet",
                    systemImage: "person.2",
                    description: Text("Add the people you play with. They'll be one tap away next round.")
                )
            }

            ForEach(players) { player in
                Button {
                    editingPlayer = player
                } label: {
                    PlayerRow(player: player)
                }
                .buttonStyle(RoundPlayRowButtonStyle())
                .roundPlayListRowSeparatorFullWidth()
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Players")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isAddingPlayer = true }
            }
        }
        .sheet(isPresented: $isAddingPlayer) {
            NavigationStack { PlayerEditSheet(player: nil) { _ in } }
        }
        .sheet(item: $editingPlayer) { player in
            NavigationStack { PlayerEditSheet(player: player) { _ in } }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(players[index]) }
        try? modelContext.save()
    }
}

/// Name, handicap, and how often you play together.
struct PlayerRow: View {
    let player: PlayerRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                if let handicap = player.handicapIndex {
                    Text("Handicap \(handicap, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No handicap")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if player.playCount > 0 {
                Text("\(player.playCount) rounds")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { PlayerListView() }.modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { PlayerListView() }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 3: Wire into `ContentView`**

Replace the `Players` tab body with `PlayerListView()`.

- [ ] **Step 4: Regenerate and commit**

```bash
cd /Users/nik/workplace/RoundPlay && xcodegen generate
git add RoundPlay
git commit -m "feat: add player roster"
```

---

### Task 4: Game library screen

**Files:**
- Create: `RoundPlay/Features/Games/GameLibraryView.swift`
- Delete: `RoundPlay/DesignSystem/DesignSystemGallery.swift`
- Modify: `RoundPlay/ContentView.swift`

**Interfaces:**
- Consumes: `GameLibrary.all`, `GameMetadata`.
- Produces: `GameLibraryView()`, `GameCard(metadata:)`.

The Games tab is where a new user learns what any of this means, so the copy carries the weight. Every card shows the plain-English `summary` from the engine — the app does not write its own descriptions, so rules and copy cannot drift apart.

- [ ] **Step 1: Write `GameLibraryView.swift`**

```swift
import SwiftUI
import RoundPlayEngine

/// The six games, with plain-English explanations.
///
/// Copy comes from `GameMetadata.summary` — defined next to each engine's rules, so a rule change
/// and its description move together.
struct GameLibraryView: View {
    var body: some View {
        RoundPlayList.plain {
            ForEach(GameLibrary.all) { metadata in
                GameCard(metadata: metadata)
                    .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Games")
    }
}

struct GameCard: View {
    let metadata: GameMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metadata.displayName).font(.headline)
                Spacer()
                Text(metadata.playerCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(metadata.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") { NavigationStack { GameLibraryView() } }
#Preview("Dark") {
    NavigationStack { GameLibraryView() }.preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Replace the Games tab and delete the gallery**

In `ContentView.swift`, change the Games tab body to `GameLibraryView()`. Then:

```bash
rm /Users/nik/workplace/RoundPlay/RoundPlay/DesignSystem/DesignSystemGallery.swift
```

- [ ] **Step 3: Regenerate and commit**

```bash
cd /Users/nik/workplace/RoundPlay && xcodegen generate
git add -A RoundPlay
git commit -m "feat: add game library screen"
```

---

### Task 5: Round creation flow

**Files:**
- Create: `RoundPlay/Features/Rounds/NewRoundFlowView.swift`
- Create: `RoundPlay/Features/Rounds/NewRoundModel.swift`
- Create: `RoundPlay/Features/Rounds/GameSetupView.swift`

**Interfaces:**
- Consumes: `CourseListView`, `PlayerRecord`, `GameLibrary`.
- Produces: `NewRoundFlowView(onStart:)`, `@Observable NewRoundModel` with `course`, `selectedPlayers`, `games`, `eligibleGames`, `canStart`, `makeRound(in:)`.

Three steps: course → players → games. Each step is one decision on one screen — no combined forms, because the target user should never be looking at two questions at once.

- [ ] **Step 1: Write `NewRoundModel.swift`**

```swift
import Foundation
import Observation
import SwiftData
import RoundPlayEngine

/// Builds a round across the three setup steps.
@Observable
final class NewRoundModel {
    var course: CourseRecord?
    var selectedPlayers: [PlayerRecord] = []
    var configurations: [GameConfiguration] = []

    /// Games whose supported player count matches the current group.
    ///
    /// Filtering rather than showing-then-erroring is deliberate: a threesome should never be
    /// offered Wolf-for-four and then told no.
    var eligibleGames: [GameMetadata] {
        GameLibrary.all.filter { $0.playerRange.contains(selectedPlayers.count) }
    }

    var canStart: Bool {
        course?.engineCourse != nil && selectedPlayers.count >= 2 && !configurations.isEmpty
    }

    func makeRound(in context: ModelContext) -> RoundRecord? {
        guard let course, course.engineCourse != nil else { return nil }

        let round = RoundRecord(courseID: course.id, courseName: course.name)
        round.seats = selectedPlayers.enumerated().map { index, player in
            SeatRecord(
                playerID: player.id,
                name: player.name,
                courseHandicap: player.courseHandicap,
                position: index
            )
        }
        round.games = configurations.compactMap { try? GameInstanceRecord(configuration: $0) }

        context.insert(round)
        course.lastPlayedAt = Date()
        for player in selectedPlayers {
            player.lastPlayedAt = Date()
            player.playCount += 1
        }
        try? context.save()
        return round
    }
}
```

- [ ] **Step 2: Write `GameSetupView.swift`**

```swift
import SwiftUI
import RoundPlayEngine

/// Pick games and set the stake for each.
struct GameSetupView: View {
    @Bindable var model: NewRoundModel
    @State private var stakes: [GameType: Decimal] = [:]

    var body: some View {
        RoundPlayList.plain {
            if model.eligibleGames.isEmpty {
                ContentUnavailableView(
                    "No games for this group size",
                    systemImage: "person.2.slash",
                    description: Text("Add or remove a player to see available games.")
                )
            }

            ForEach(model.eligibleGames) { metadata in
                GameSelectionRow(
                    metadata: metadata,
                    isSelected: isSelected(metadata.gameType),
                    stake: stakeBinding(for: metadata.gameType),
                    onToggle: { toggle(metadata.gameType) }
                )
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Games")
    }

    private func isSelected(_ type: GameType) -> Bool {
        model.configurations.contains { $0.gameType == type }
    }

    private func stakeBinding(for type: GameType) -> Binding<Decimal> {
        Binding(
            get: { stakes[type] ?? 5 },
            set: { stakes[type] = $0; rebuild(type) }
        )
    }

    private func toggle(_ type: GameType) {
        if isSelected(type) {
            model.configurations.removeAll { $0.gameType == type }
        } else {
            model.configurations.append(configuration(for: type, stake: stakes[type] ?? 5))
        }
    }

    private func rebuild(_ type: GameType) {
        guard isSelected(type) else { return }
        model.configurations.removeAll { $0.gameType == type }
        model.configurations.append(configuration(for: type, stake: stakes[type] ?? 5))
    }

    /// Defaults come from each engine's documented convention, not from the UI's imagination.
    private func configuration(for type: GameType, stake: Decimal) -> GameConfiguration {
        switch type {
        case .skins: .skins(SkinsConfig(unitStake: stake))
        case .nassau: .nassau(NassauConfig(unitStake: stake))
        case .stableford: .stableford(StablefordConfig(unitStake: stake))
        case .nines: .nines(NinesConfig(unitStake: stake))
        case .wolf: .wolf(.standard(unitStake: stake))
        case .bingoBangoBongo: .bingoBangoBongo(BingoBangoBongoConfig(unitStake: stake))
        }
    }
}

private struct GameSelectionRow: View {
    let metadata: GameMetadata
    let isSelected: Bool
    @Binding var stake: Decimal
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? RoundPlayColors.accent : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metadata.displayName).font(.headline)
                        Text(metadata.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                HStack {
                    Text("Stake")
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { NSDecimalNumber(decimal: stake).intValue },
                            set: { stake = Decimal($0) }
                        ),
                        in: 1...100
                    ) {
                        Text(stake, format: .currency(code: "USD"))
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Light") {
    let model = NewRoundModel()
    return NavigationStack { GameSetupView(model: model) }
}
```

- [ ] **Step 3: Write `NewRoundFlowView.swift`**

```swift
import SwiftUI
import SwiftData

/// Three-step round setup: course, players, games.
struct NewRoundFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model = NewRoundModel()
    @State private var path = NavigationPath()

    let onStart: (RoundRecord) -> Void

    private enum Step: Hashable { case players, games }

    var body: some View {
        NavigationStack(path: $path) {
            CourseListView { course in
                model.course = course
                path.append(Step.players)
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .players:
                    PlayerSelectionStep(model: model) { path.append(Step.games) }
                case .games:
                    GameSetupView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Start") { start() }.disabled(!model.canStart)
                            }
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func start() {
        guard let round = model.makeRound(in: modelContext) else { return }
        onStart(round)
        dismiss()
    }
}

/// Who's playing. Roster first, sorted by recency — the regular group is at the top.
private struct PlayerSelectionStep: View {
    @Bindable var model: NewRoundModel
    let onContinue: () -> Void

    @Query(sort: [SortDescriptor(\PlayerRecord.lastPlayedAt, order: .reverse),
                  SortDescriptor(\PlayerRecord.name)])
    private var players: [PlayerRecord]

    @State private var isAddingPlayer = false

    var body: some View {
        RoundPlayList.plain {
            ForEach(players) { player in
                Button {
                    toggle(player)
                } label: {
                    HStack {
                        Image(systemName: isSelected(player) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isSelected(player) ? RoundPlayColors.accent : .secondary)
                        PlayerRow(player: player)
                    }
                }
                .buttonStyle(RoundPlayRowButtonStyle())
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Players")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New", systemImage: "plus") { isAddingPlayer = true }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next", action: onContinue)
                    .disabled(model.selectedPlayers.count < 2)
            }
        }
        .sheet(isPresented: $isAddingPlayer) {
            NavigationStack {
                PlayerEditSheet(player: nil) { model.selectedPlayers.append($0) }
            }
        }
    }

    private func isSelected(_ player: PlayerRecord) -> Bool {
        model.selectedPlayers.contains { $0.id == player.id }
    }

    private func toggle(_ player: PlayerRecord) {
        if isSelected(player) {
            model.selectedPlayers.removeAll { $0.id == player.id }
        } else {
            model.selectedPlayers.append(player)
        }
    }
}

#Preview("Light") {
    NewRoundFlowView { _ in }.modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NewRoundFlowView { _ in }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 4: Regenerate and commit**

```bash
cd /Users/nik/workplace/RoundPlay && xcodegen generate
git add RoundPlay
git commit -m "feat: add round creation flow"
```

---

### Task 6: The hole screen

**Files:**
- Create: `RoundPlay/Features/Scoring/HoleScreenView.swift`
- Create: `RoundPlay/Features/Scoring/ScoreStripView.swift`
- Create: `RoundPlay/Features/Scoring/WolfPromptView.swift`
- Create: `RoundPlay/Features/Scoring/HoleEventsPromptView.swift`

**Interfaces:**
- Consumes: `EngineBridge`, `RoundState`, `GameLibrary.metadata(for:)`, `RoundPlayColors`.
- Produces: `HoleScreenView(round:course:)`, `ScoreStripView(par:selected:onSelect:)`, `WolfPromptView(...)`, `HoleEventsPromptView(...)`.

**This is the most-repeated interaction in the app** — up to 72 entries a round, outdoors, in sun, often by someone in their seventies. Everything else is scaffolding around it.

Design rules, from the spec:
- One screen per hole; a row per player — it *is* the paper scorecard.
- The number strip is **centered on the hole's par**: for a par 4, `3 4 5 6 7` plus an overflow. Five thumb-sized targets cover ~95% of real scores.
- Game prompts render from `requiredInputs`. The view **never switches on game type.**

- [ ] **Step 1: Write `ScoreStripView.swift`**

```swift
import SwiftUI

/// The number strip for one player on one hole.
///
/// Centered on par rather than showing 1–12: a par 4 offers `3 4 5 6 7`, which covers the
/// overwhelming majority of real scores in five targets big enough to hit without looking.
/// Disasters go through "More", which is rare enough to deserve the extra tap.
struct ScoreStripView: View {
    let par: Int
    let selected: Int?
    let onSelect: (Int) -> Void

    @State private var isShowingOverflow = false

    /// Par − 1 through par + 3.
    private var range: [Int] {
        Array(max(1, par - 1)...(par + 3))
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(range, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Text("\(value)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(value == selected
                                      ? RoundPlayColors.accent
                                      : RoundPlayColors.fillSecondary)
                        )
                        .foregroundStyle(value == selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Score \(value)")
                .accessibilityAddTraits(value == selected ? [.isSelected] : [])
            }

            Button {
                isShowingOverflow = true
            } label: {
                Text("…")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(RoundPlayColors.fillTertiary)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More scores")
        }
        .confirmationDialog("Score", isPresented: $isShowingOverflow) {
            ForEach(1...15, id: \.self) { value in
                Button("\(value)") { onSelect(value) }
            }
        }
    }
}

#Preview("Par 4, nothing selected") {
    ScoreStripView(par: 4, selected: nil) { _ in }.padding()
}

#Preview("Par 3, five selected") {
    ScoreStripView(par: 3, selected: 5) { _ in }.padding()
}

#Preview("Dark") {
    ScoreStripView(par: 5, selected: 5) { _ in }
        .padding()
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Write `WolfPromptView.swift`**

```swift
import SwiftUI
import RoundPlayEngine

/// The Wolf's per-hole decision, shown before scores are entered.
///
/// Rendered whenever any active game declares `.partnerChoice` — this view is reached through the
/// input declaration, not through a check for "is this Wolf".
struct WolfPromptView: View {
    let wolfName: String
    let candidates: [(id: UUID, name: String)]
    let declaration: WolfDeclaration?
    let onDeclare: (WolfDeclaration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(wolfName) is the Wolf")
                .font(.subheadline.weight(.semibold))

            Text("Pick a partner after their tee shot, or go it alone for quadruple points.")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(candidates, id: \.id) { candidate in
                    ChipButton(
                        title: candidate.name,
                        isSelected: declaration == .partner(candidate.id)
                    ) {
                        onDeclare(.partner(candidate.id))
                    }
                }
                ChipButton(title: "Lone Wolf", isSelected: declaration == .lone) {
                    onDeclare(.lone)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview("Light") {
    WolfPromptView(
        wolfName: "Ann",
        candidates: [(UUID(), "Ben"), (UUID(), "Cal"), (UUID(), "Dee")],
        declaration: nil
    ) { _ in }
    .padding()
}

#Preview("Dark") {
    WolfPromptView(
        wolfName: "Ann",
        candidates: [(UUID(), "Ben"), (UUID(), "Cal"), (UUID(), "Dee")],
        declaration: .lone
    ) { _ in }
    .padding()
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 3: Write `HoleEventsPromptView.swift`**

```swift
import SwiftUI
import RoundPlayEngine

/// Bingo Bango Bongo's three per-hole awards.
///
/// Rendered whenever any active game declares `.holeEvents`. Labels use plain English rather than
/// the game's jargon, because a first-time player has no idea what "bango" means.
struct HoleEventsPromptView: View {
    let players: [(id: UUID, name: String)]
    /// Current winner for each award, if recorded.
    let winners: [HoleEventKind: UUID]
    let onAward: (HoleEventKind, UUID) -> Void

    private func label(for kind: HoleEventKind) -> String {
        switch kind {
        case .bingo: "First on the green"
        case .bango: "Closest to the pin"
        case .bongo: "First in the hole"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(HoleEventKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label(for: kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(players, id: \.id) { player in
                            ChipButton(
                                title: player.name,
                                isSelected: winners[kind] == player.id
                            ) {
                                onAward(kind, player.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview("Light") {
    HoleEventsPromptView(
        players: [(UUID(), "Ann"), (UUID(), "Ben"), (UUID(), "Cal")],
        winners: [:]
    ) { _, _ in }
    .padding()
}

#Preview("Dark") {
    HoleEventsPromptView(
        players: [(UUID(), "Ann"), (UUID(), "Ben"), (UUID(), "Cal")],
        winners: [:]
    ) { _, _ in }
    .padding()
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 4: Write `HoleScreenView.swift`**

```swift
import SwiftUI
import SwiftData
import RoundPlayEngine

/// One hole, one screen — the paper scorecard.
///
/// Prompts are driven entirely by the union of `requiredInputs` across the round's active games.
/// This view has no idea what Wolf or Bingo Bango Bongo *are*; it knows that some game needs a
/// partner choice, or three hole events, and renders accordingly.
struct HoleScreenView: View {
    @Environment(\.modelContext) private var modelContext

    let round: RoundRecord
    let course: Course

    @State private var hole: Int = 1

    private var state: RoundState {
        EngineBridge.roundState(for: round, course: course)
    }

    private var requiredInputs: Set<InputKind> {
        (round.games ?? []).reduce(into: Set<InputKind>()) { partial, game in
            guard let type = game.gameType else { return }
            partial.formUnion(GameLibrary.metadata(for: type).requiredInputs)
        }
    }

    /// Whoever is entering scores. Phase 1 is single-device, so this is always the first seat;
    /// Phase 2 replaces it with the signed-in account.
    private var scorekeeper: SeatRecord? { round.orderedSeats.first }

    var body: some View {
        VStack(spacing: 0) {
            HoleHeader(hole: hole, par: course.hole(hole)?.par ?? 4,
                       strokeIndex: course.hole(hole)?.strokeIndex ?? 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if requiredInputs.contains(.partnerChoice) { wolfPrompt }

                    ForEach(round.orderedSeats) { seat in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(seat.name).font(.headline)
                                if state.strokesReceived(hole: hole, player: seat.playerID) > 0 {
                                    Text("•")
                                        .foregroundStyle(RoundPlayColors.accent)
                                        .accessibilityLabel("Gets a stroke on this hole")
                                }
                                Spacer()
                            }
                            ScoreStripView(
                                par: course.hole(hole)?.par ?? 4,
                                selected: state.gross(hole: hole, player: seat.playerID)
                            ) { strokes in
                                record(strokes: strokes, for: seat)
                            }
                        }
                    }

                    if requiredInputs.contains(.holeEvents) { holeEventsPrompt }
                }
                .padding()
            }

            HoleNavigationBar(
                hole: $hole,
                isComplete: state.isComplete(hole: hole)
            )
        }
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var wolfPrompt: some View {
        let seats = round.orderedSeats
        if !seats.isEmpty {
            let wolfSeat = seats[(hole - 1) % seats.count]
            WolfPromptView(
                wolfName: wolfSeat.name,
                candidates: seats
                    .filter { $0.playerID != wolfSeat.playerID }
                    .map { (id: $0.playerID, name: $0.name) },
                declaration: state.wolfDeclaration(hole: hole)?.declaration
            ) { declaration in
                guard let scorekeeper else { return }
                try? EngineBridge.appendWolfDeclaration(
                    declaration, hole: hole, wolfID: wolfSeat.playerID, to: round,
                    enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
                    in: modelContext
                )
            }
        }
    }

    @ViewBuilder
    private var holeEventsPrompt: some View {
        let winners = HoleEventKind.allCases.reduce(into: [HoleEventKind: UUID]()) { partial, kind in
            partial[kind] = state.holeEventWinner(hole: hole, kind: kind)
        }
        HoleEventsPromptView(
            players: round.orderedSeats.map { (id: $0.playerID, name: $0.name) },
            winners: winners
        ) { kind, playerID in
            guard let scorekeeper else { return }
            try? EngineBridge.appendHoleEvent(
                kind, hole: hole, playerID: playerID, to: round,
                enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
                in: modelContext
            )
        }
    }

    private func record(strokes: Int, for seat: SeatRecord) {
        guard let scorekeeper else { return }
        try? EngineBridge.appendStrokes(
            strokes, hole: hole, playerID: seat.playerID, to: round,
            enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
            in: modelContext
        )
    }
}

/// Hole number, par, and stroke index — the three facts a golfer checks on the tee.
private struct HoleHeader: View {
    let hole: Int
    let par: Int
    let strokeIndex: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Hole \(hole)").font(.largeTitle.weight(.bold))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Par \(par)").font(.headline)
                Text("SI \(strokeIndex)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(RoundPlayColors.backgroundSecondaryGrouped)
    }
}

private struct HoleNavigationBar: View {
    @Binding var hole: Int
    let isComplete: Bool

    var body: some View {
        HStack {
            Button {
                hole = max(1, hole - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(hole == 1)

            Spacer()

            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isComplete
                                 ? RoundPlayColors.scoreUnderPar
                                 : RoundPlayColors.holePending)
                .accessibilityLabel(isComplete ? "Hole complete" : "Hole incomplete")

            Spacer()

            Button {
                hole = min(18, hole + 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(hole == 18)
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .padding(.horizontal)
        .background(RoundPlayColors.backgroundSecondaryGrouped)
    }
}

#Preview("Light") {
    NavigationStack {
        HoleScreenView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack {
        HoleScreenView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 5: Add the preview course helper**

Append to `RoundPlay/Support/PreviewData.swift`:

```swift
import RoundPlayEngine

extension Course {
    /// Engine course matching `PreviewData`'s Pebble Creek.
    static var previewCourse: Course {
        let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4]
        let strokeIndexes = [1, 11, 17, 3, 7, 15, 13, 5, 9, 2, 16, 12, 4, 8, 18, 14, 6, 10]
        let holes = (0..<18).map {
            Hole(number: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0])
        }
        return Course(id: UUID(), name: "Pebble Creek", holes: holes)
    }
}
```

- [ ] **Step 6: Regenerate and commit**

```bash
cd /Users/nik/workplace/RoundPlay && xcodegen generate
git add RoundPlay
git commit -m "feat: add hole screen with declaration-driven prompts"
```

**User verification (the important one):** open the `HoleScreenView` previews in both appearances. Check that number targets are comfortably thumb-sized, that the stroke dot appears next to players receiving a shot, and that the screen is legible at the largest Dynamic Type setting.

---

### Task 7: Dashboard, audit log, and the Settle Up stub

**Files:**
- Create: `RoundPlay/Features/Rounds/RoundDashboardView.swift`
- Create: `RoundPlay/Features/Rounds/AuditLogView.swift`
- Create: `RoundPlay/Features/Rounds/RoundsHomeView.swift`
- Modify: `RoundPlay/ContentView.swift`

**Interfaces:**
- Consumes: `EngineBridge.settlements(for:course:)`, `Settlement`, `HoleExplanation`.
- Produces: `RoundDashboardView(round:course:)`, `AuditLogView(round:)`, `RoundsHomeView()`.

- [ ] **Step 1: Write `RoundDashboardView.swift`**

```swift
import SwiftUI
import SwiftData
import RoundPlayEngine

/// Live standings and money for every game in the round.
///
/// Every figure comes from `Settlement`. The dashboard performs no arithmetic of its own — if a
/// number is wrong here, the bug is in the engine and there is a failing fixture to write.
struct RoundDashboardView: View {
    let round: RoundRecord
    let course: Course

    private var settlements: [Settlement] {
        EngineBridge.settlements(for: round, course: course)
    }

    private func name(for playerID: UUID) -> String {
        round.orderedSeats.first { $0.playerID == playerID }?.name ?? "Unknown"
    }

    var body: some View {
        RoundPlayList.plain {
            ForEach(settlements, id: \.gameType) { settlement in
                Section {
                    ForEach(settlement.standings.sorted { $0.money > $1.money }) { standing in
                        HStack {
                            Text(name(for: standing.playerID))
                            Spacer()
                            Text("\(standing.points) pts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(standing.money, format: .currency(code: "USD"))
                                .monospacedDigit()
                                .foregroundStyle(moneyColor(standing.money))
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                        .roundPlayListRowSeparatorFullWidth()
                    }

                    if !settlement.holeExplanations.isEmpty {
                        DisclosureGroup("Hole by hole") {
                            // Indexed rather than keyed on `text`: Nassau emits two explanations
                            // for one hole (the result, then a press opening), and identical
                            // strings across holes are common ("Hole 4: halved.").
                            ForEach(Array(settlement.holeExplanations.enumerated()), id: \.offset) { _, explanation in
                                Text(explanation.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(GameLibrary.metadata(for: settlement.gameType).displayName)
                }
            }

            Section {
                SettleUpStub()
            }
        }
        .navigationTitle("Standings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { AuditLogView(round: round) } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private func moneyColor(_ amount: Decimal) -> Color {
        if amount > 0 { return RoundPlayColors.moneyPositive }
        if amount < 0 { return RoundPlayColors.moneyNegative }
        return RoundPlayColors.moneyEven
    }
}

/// Payments are Phase 5. The affordance ships now, disabled, so the shape of the app is honest
/// about where it is going — and so the ledger has a home when it arrives.
private struct SettleUpStub: View {
    var body: some View {
        VStack(spacing: 6) {
            Button("Settle Up") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
            Text("Coming soon — for now, settle up however you normally do.")
                .font(.caption)
                .foregroundStyle(RoundPlayColors.moneyDisabled)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

#Preview("Light") {
    NavigationStack {
        RoundDashboardView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack {
        RoundDashboardView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Write `AuditLogView.swift`**

```swift
import SwiftUI
import RoundPlayEngine

/// Every entry ever made in this round, newest first.
///
/// This is the append-only log read backwards — no separate audit table exists, and none is
/// needed. A corrected score shows as two entries, which is exactly the point: "Ben changed your
/// 6 to a 5 on 14" is visible rather than silent.
struct AuditLogView: View {
    let round: RoundRecord

    private var entries: [ScoreEventRecord] {
        (round.events ?? []).sorted { $0.sequence > $1.sequence }
    }

    private func name(for playerID: UUID) -> String {
        round.orderedSeats.first { $0.playerID == playerID }?.name ?? "Unknown"
    }

    private func describe(_ record: ScoreEventRecord) -> String {
        switch record.payload {
        case .strokes(let count):
            "\(name(for: record.playerID)) scored \(count)"
        case .wolfDeclaration(.lone):
            "\(name(for: record.playerID)) went Lone Wolf"
        case .wolfDeclaration(.partner(let partner)):
            "\(name(for: record.playerID)) partnered with \(name(for: partner))"
        case .holeEvent(let kind):
            "\(name(for: record.playerID)) took the \(kind.rawValue)"
        case nil:
            "Unreadable entry"
        }
    }

    var body: some View {
        RoundPlayList.plain {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing recorded yet",
                    systemImage: "clock",
                    description: Text("Scores appear here as they're entered.")
                )
            }

            ForEach(entries) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hole \(record.hole) — \(describe(record))")
                    Text("Entered by \(record.enteredByName) · \(record.recordedAt, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Light") {
    NavigationStack { AuditLogView(round: PreviewData.sampleRound) }
        .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { AuditLogView(round: PreviewData.sampleRound) }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 3: Write `RoundsHomeView.swift`**

```swift
import SwiftUI
import SwiftData
import RoundPlayEngine

/// The Rounds tab: start a round, or resume one in progress.
struct RoundsHomeView: View {
    @Query(sort: \RoundRecord.startedAt, order: .reverse) private var rounds: [RoundRecord]
    @Query private var courses: [CourseRecord]

    @State private var isCreatingRound = false
    @State private var activeRound: RoundRecord?

    private func course(for round: RoundRecord) -> Course? {
        courses.first { $0.id == round.courseID }?.engineCourse
    }

    var body: some View {
        RoundPlayList.plain {
            if rounds.isEmpty {
                ContentUnavailableView(
                    "No rounds yet",
                    systemImage: "flag.circle",
                    description: Text("Start a round and keep score for your group.")
                )
            }

            ForEach(rounds) { round in
                NavigationLink {
                    if let course = course(for: round) {
                        RoundTabsView(round: round, course: course)
                    } else {
                        ContentUnavailableView(
                            "Course unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text("The course for this round is missing or incomplete.")
                        )
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(round.courseName).font(.body)
                        Text("\(round.orderedSeats.count) players · \(round.startedAt, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Rounds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Round", systemImage: "plus") { isCreatingRound = true }
            }
        }
        .sheet(isPresented: $isCreatingRound) {
            NewRoundFlowView { activeRound = $0 }
        }
    }
}

/// Scoring and standings for a round in progress.
struct RoundTabsView: View {
    let round: RoundRecord
    let course: Course

    var body: some View {
        TabView {
            Tab("Scorecard", systemImage: "square.grid.3x3") {
                NavigationStack { HoleScreenView(round: round, course: course) }
            }
            Tab("Standings", systemImage: "chart.bar") {
                NavigationStack { RoundDashboardView(round: round, course: course) }
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { RoundsHomeView() }.modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { RoundsHomeView() }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 4: Wire the Rounds tab**

In `ContentView.swift`, change the Rounds tab body to `RoundsHomeView()`.

- [ ] **Step 5: Regenerate and commit**

```bash
cd /Users/nik/workplace/RoundPlay && xcodegen generate
git add RoundPlay
git commit -m "feat: add round dashboard, audit log, and settle-up stub"
```

---

## Phase 1b exit criteria

- [ ] `cd Packages/RoundPlayEngine && swift test` still passes.
- [ ] `grep -rn "UpKeepr" RoundPlay/` returns nothing.
- [ ] Every view has light and dark previews using `PreviewData`.
- [ ] No scoring arithmetic exists outside `RoundPlayEngine`.

**User run-through (the real exit criterion).** In Xcode, on a phone-sized simulator:

1. Add a course from a real scorecard — 18 pars and stroke indexes.
2. Add four players with real, differing handicaps.
3. Start a round with Skins and Wolf both selected.
4. Score all 18 holes, including at least one Lone Wolf and one correction.
5. Check the standings against a hand calculation. **If they disagree, the engine is wrong** — write the failing fixture before touching any UI.
6. Open the history view and confirm the correction shows both entries.
7. Repeat in dark mode and at the largest Dynamic Type setting.

## What Phase 1 deliberately does not do

- No backend, no sync, no join codes, no QR — Phase 2.
- No accounts — Phase 2.
- **Single device only.** The scorekeeper is hardcoded to the first seat, which is the honest shape of a single-device app; Phase 2 replaces it with the signed-in account.
- No voice — Phase 3.
- No real settlement — Phase 5.
