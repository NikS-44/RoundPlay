import Foundation
import Observation
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// One seat in the round being built.
///
/// Starts as a placeholder: a random nickname nobody typed, shown with different styling so it
/// reads as "not yet confirmed" rather than a real entry. A placeholder never blocks starting the
/// round — it only becomes a permanent roster `PlayerRecord` if someone actually renames or
/// assigns it; left untouched, it exists for this round only and leaves no trace afterward.
@Observable
final class RoundSeatDraft: Identifiable {
    let id = UUID()
    var assignedPlayer: PlayerRecord?
    var guestName: String = ""
    var guestHandicap: Double?
    /// Renaming a placeholder is round-only unless the user deliberately chooses the roster
    /// action in the assignment sheet.
    var shouldAddToRoster = false
    /// True until the seat is explicitly assigned or renamed. Drives both the "Placeholder" tag
    /// and whether this seat's guest gets saved to the roster.
    var isPlaceholder = true

    var isAnonymous: Bool { assignedPlayer == nil }

    var displayName: String {
        if let assignedPlayer { return assignedPlayer.name }
        return guestName.isEmpty ? "Unassigned" : guestName
    }

    var handicapLabel: String {
        let handicap = assignedPlayer?.handicapIndex ?? guestHandicap
        guard let handicap else { return "No handicap" }
        return "Handicap \(handicap.formatted(.number.precision(.fractionLength(0...1))))"
    }

    /// The handicap index this seat carries into the round, if any. `nil` means nobody has said —
    /// which the strokes step treats as new information worth offering to save.
    var handicapIndexForRound: Double? {
        assignedPlayer?.handicapIndex ?? guestHandicap
    }

    /// Whole-stroke course handicap for this seat. Matches `PlayerRecord.courseHandicap`: the app
    /// doesn't collect slope or course rating, so a rounded index is the course handicap.
    var courseHandicapForRound: Int {
        Int((handicapIndexForRound ?? 0).rounded())
    }

    /// A seat is ready once it names someone — assigned or given a guest nickname. Placeholders
    /// count: that's the whole point of auto-nicknaming, so counting/players/games never blocks
    /// on someone confirming who's who.
    var isFilled: Bool { assignedPlayer != nil || !guestName.isEmpty }

    func assign(to player: PlayerRecord) {
        assignedPlayer = player
        isPlaceholder = false
    }

    /// Gives the seat its own name instead of the roster — always persisted, since typing a name
    /// is an explicit "this is a real person" signal.
    func rename(to name: String, handicap: Double?, addToRoster: Bool = false) {
        assignedPlayer = nil
        guestName = name
        guestHandicap = handicap
        isPlaceholder = false
        shouldAddToRoster = addToRoster
    }

    /// Resolves this seat to the `PlayerRecord` it should use in the round. Placeholders that
    /// were never touched are **not** inserted into the model context — they exist only as a
    /// name/handicap pair on the `SeatRecord` itself, so an untouched "Birdie Malone" never shows
    /// up in the Players tab afterward.
    func resolvedForRound(in context: ModelContext) -> (playerID: UUID, name: String, courseHandicap: Int, persistedPlayer: PlayerRecord?) {
        if let assignedPlayer {
            return (assignedPlayer.id, assignedPlayer.name, assignedPlayer.courseHandicap, assignedPlayer)
        }
        guard !guestName.isEmpty else {
            return (UUID(), "Unassigned", 0, nil)
        }
        if isPlaceholder {
            let handicap = Int((guestHandicap ?? 0).rounded())
            return (UUID(), guestName, handicap, nil)
        }
        guard shouldAddToRoster else {
            return (UUID(), guestName, Int((guestHandicap ?? 0).rounded()), nil)
        }
        let record = PlayerRecord(name: guestName, handicapIndex: guestHandicap)
        context.insert(record)
        assignedPlayer = record
        return (record.id, record.name, record.courseHandicap, record)
    }
}

/// Builds a round across the setup steps: course, players, games.
@Observable
final class NewRoundModel {
    var course: CourseRecord?
    var seats: [RoundSeatDraft] = Array(repeating: (), count: 4).map { _ in RoundSeatDraft() }
    var configurations: [GameConfiguration] = []
    /// Team A's seat positions for Best Ball. Team B is the remaining two seats.
    var bestBallTeamA: Set<Int> = [0, 1]
    /// Which holes this round plays. Defaults to all 18 — front/back-9-only is the exception.
    var holeSegment: RoundSegment = .total
    /// Set when the flow was launched from a game's rules screen — that game is pre-selected
    /// and its stake row expanded in the games step.
    var preselectedGameType: GameType?
    /// Set when the flow was launched with a favorite course already chosen (e.g. from
    /// onboarding) — skips straight past the course step.
    var skipsCourseStep = false

    /// How the group agreed to handle strokes. Defaults to off-the-low because that's how every
    /// hole-by-hole money game is actually played.
    var handicapSettings: HandicapSettings = .default
    /// Strokes a seat was given by hand on the strokes step, keyed by seat id.
    ///
    /// An override is a number the group agreed out loud ("you give me four"), so it replaces the
    /// computed playing handicap outright rather than feeding back through allowance and mode.
    var strokeOverrides: [UUID: Int] = [:]

    // MARK: - Step numbering

    /// The screens the round builder can walk through, in order.
    ///
    /// Two of them are conditional — `fillRemaining` is skipped when the roster already filled
    /// every seat, and `bestBallTeams` only exists for Best Ball — so the step labels can't be
    /// hardcoded per screen. They were, and disagreed: the course step said "Step 1 of 6" while
    /// every screen after it said "of 7", and a group that filled all four seats from the roster
    /// counted 1, 2, 3, 5, 6 with no step 4 in sight.
    enum BuilderStep: CaseIterable {
        case course, playerCount, knownPlayers, fillRemaining, strokes, holes, games, bestBallTeams
    }

    /// Only the steps this particular round will actually show.
    private var activeSteps: [BuilderStep] {
        BuilderStep.allCases.filter { step in
            switch step {
            case .course: !skipsCourseStep
            case .fillRemaining: seats.contains(where: \.isAnonymous)
            case .bestBallTeams: configurations.contains { $0.gameType == .bestBall }
            default: true
            }
        }
    }

    var totalSteps: Int { activeSteps.count }

    // MARK: - Strokes

    /// Strokes each seat will actually receive, keyed by seat draft id.
    ///
    /// Runs the real engine computation over throwaway seats rather than reimplementing allowance,
    /// cap and off-the-low in the view layer — the number on the setup screen has to be the number
    /// the scorecard uses, or the group agreed to something the app didn't do.
    var strokesBySeat: [UUID: Int] {
        let probes = seats.map { draft in
            Seat(
                playerID: draft.id,
                name: draft.displayName,
                courseHandicap: draft.courseHandicapForRound,
                strokeOverride: strokeOverrides[draft.id]
            )
        }
        return PlayingHandicap.byPlayer(seats: probes, settings: handicapSettings)
    }

    func strokes(for draft: RoundSeatDraft) -> Int {
        strokesBySeat[draft.id] ?? 0
    }

    /// The seat playing off scratch under off-the-low — everyone else is giving or receiving
    /// relative to this player, which is what the group says out loud.
    var lowSeat: RoundSeatDraft? {
        seats.min { $0.courseHandicapForRound < $1.courseHandicapForRound }
    }

    /// Allowance the chosen games recommend, or `nil` when they disagree or none applies.
    ///
    /// Four-ball formats (Best Ball) carry the lowest allowances because a team taking the better
    /// of two balls compounds high handicaps.
    var recommendedAllowance: Int? {
        guard !configurations.isEmpty else { return nil }
        let recommendations = Set(configurations.map { configuration -> Int in
            switch configuration.gameType {
            case .bestBall: 85
            case .matchPlay: 100
            case .stableford, .strokePlay: 95
            default: 100
            }
        })
        return recommendations.count == 1 ? recommendations.first : nil
    }

    /// 1-based position of `step` among the steps actually being shown. Falls back to the
    /// unconditional ordering if asked about a step this round skips, so a label can never read
    /// "Step 0".
    func stepNumber(for step: BuilderStep) -> Int {
        guard let index = activeSteps.firstIndex(of: step) else {
            return (BuilderStep.allCases.firstIndex(of: step) ?? 0) + 1
        }
        return index + 1
    }

    var playerCount: Int {
        get { seats.count }
        set {
            let count = max(2, min(8, newValue))
            if count < seats.count {
                seats.removeLast(seats.count - count)
            } else if count > seats.count {
                seats.append(contentsOf: (seats.count..<count).map { _ in RoundSeatDraft() })
            }
        }
    }

    /// Games whose supported player count matches the current group.
    ///
    /// Filtering rather than showing-then-erroring is deliberate: a threesome should never be
    /// offered Wolf-for-four and then told no.
    var eligibleGames: [GameMetadata] {
        GameLibrary.all.filter { metadata in
            guard metadata.playerRange.contains(seats.count) else { return false }
            // Nassau's three bets are defined over a full 18-hole round in this release.
            return !(metadata.gameType == .nassau && holeSegment != .total)
        }
    }

    var allSeatsFilled: Bool { seats.allSatisfy(\.isFilled) }

    var bestBallTeamsComplete: Bool {
        !configurations.contains(where: { $0.gameType == .bestBall }) || bestBallTeamA.count == 2
    }

    /// Games are optional — a group that just wants a scorecard, no bets, still gets a normal
    /// stroke-play round.
    var canStart: Bool {
        course?.engineCourse != nil && seats.count >= 1 && allSeatsFilled && bestBallTeamsComplete
    }

    /// Every name already spoken for in this round — assigned players and guests already
    /// nicknamed — so a new guest nickname never collides with a seatmate.
    var namesInUse: Set<String> {
        Set(seats.compactMap { $0.assignedPlayer?.name ?? ($0.guestName.isEmpty ? nil : $0.guestName) })
    }

    /// Builds a model prefilled from a finished round — same course, same seats (roster players
    /// re-linked by id, guests carried over by name/handicap), same games and stakes. "Play Again"
    /// is this plus a confirmation screen, not the six-step builder from scratch.
    static func replaying(_ round: RoundRecord, course: CourseRecord, in context: ModelContext) -> NewRoundModel {
        let model = NewRoundModel()
        model.course = course
        model.holeSegment = round.holeSegment
        model.seats = round.orderedSeats.map { seat in
            let draft = RoundSeatDraft()
            let playerID = seat.playerID
            let descriptor = FetchDescriptor<PlayerRecord>(predicate: #Predicate { $0.id == playerID })
            if let player = try? context.fetch(descriptor).first {
                draft.assign(to: player)
            } else {
                // No roster match means this was an untouched anonymous guest last time — carry
                // the same nickname forward for continuity, but *don't* call `rename(to:)`: that
                // marks a seat as explicitly confirmed, and `makeRound` would then persist it to
                // the roster. An anonymized name should never end up there just because it's
                // being replayed; it only becomes permanent if someone renames it again here.
                draft.guestName = seat.name
                draft.guestHandicap = Double(seat.courseHandicap)
            }
            return draft
        }
        model.configurations = (round.games ?? []).compactMap { $0.configuration }
        return model
    }

    func makeRound(in context: ModelContext) -> RoundRecord? {
        guard let course, course.engineCourse != nil else { return nil }

        let round = RoundRecord(courseID: course.id, courseName: course.name, holeSegment: holeSegment)
        round.handicapSettings = handicapSettings
        var seatRecords: [SeatRecord] = []
        for (index, draft) in seats.enumerated() {
            let resolved = draft.resolvedForRound(in: context)
            let seatRecord = SeatRecord(
                playerID: resolved.playerID,
                name: resolved.name,
                courseHandicap: resolved.courseHandicap,
                position: index
            )
            seatRecord.strokeOverride = strokeOverrides[draft.id]
            seatRecords.append(seatRecord)
            if let player = resolved.persistedPlayer {
                player.lastPlayedAt = Date()
                player.playCount += 1
            }
        }
        round.seats = seatRecords
        round.games = configurations.compactMap { try? GameInstanceRecord(configuration: $0) }

        context.insert(round)
        course.lastPlayedAt = Date()
        try? context.save()
        EngineBridge.onLocalChange?()
        return round
    }
}
