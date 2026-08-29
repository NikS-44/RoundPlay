import Foundation

/// The append-only event log folded into current values.
///
/// This is the single place the log→state reduction happens. Every engine reads `RoundState`
/// and never touches raw events, so "latest recordedAt wins" is defined exactly once.
public struct RoundState: Sendable {
    public let seats: [Seat]
    public let course: Course
    public let segment: RoundSegment
    public let handicapSettings: HandicapSettings

    /// Playing handicap per player, resolved once at init rather than per `strokesReceived` call —
    /// `offTheLow` depends on every other seat, so recomputing it per hole per player would be
    /// quadratic across a scorecard render.
    private let playingHandicaps: [UUID: Int]

    /// Latest-recordedAt stroke entry per (hole, player).
    private let strokesByHolePlayer: [HolePlayer: Int]
    /// Latest-recordedAt Wolf declaration per hole.
    private let wolfByHole: [Int: (wolf: UUID, declaration: WolfDeclaration)]
    /// Latest-recordedAt winner per (hole, event kind).
    private let holeEvents: [HoleEventKey: UUID]
    /// Latest-recordedAt press answer per hole — the hole the press would start on.
    private let pressesByHole: [Int: (player: UUID, decision: PressDecision)]

    private struct HolePlayer: Hashable {
        let hole: Int
        let player: UUID
    }

    private struct HoleEventKey: Hashable {
        let hole: Int
        let kind: HoleEventKind
    }

    public init(
        log: [ScoreEvent],
        seats: [Seat],
        course: Course,
        segment: RoundSegment = .total,
        handicapSettings: HandicapSettings = .default
    ) {
        self.seats = seats
        self.course = course
        self.segment = segment
        self.handicapSettings = handicapSettings
        self.playingHandicaps = PlayingHandicap.byPlayer(seats: seats, settings: handicapSettings)

        // Sorting ascending and letting later writes overwrite gives "latest recordedAt wins"
        // without a comparison in the loop. Ties on time are broken by event id.
        let ordered = log.sorted(by: ScoreEvent.foldAscending)

        var strokes: [HolePlayer: Int] = [:]
        var wolf: [Int: (wolf: UUID, declaration: WolfDeclaration)] = [:]
        var events: [HoleEventKey: UUID] = [:]
        var presses: [Int: (player: UUID, decision: PressDecision)] = [:]

        for event in ordered {
            switch event.payload {
            case .strokes(let count):
                strokes[HolePlayer(hole: event.hole, player: event.playerID)] = count
            case .wolfDeclaration(let declaration):
                wolf[event.hole] = (wolf: event.playerID, declaration: declaration)
            case .holeEvent(let kind):
                events[HoleEventKey(hole: event.hole, kind: kind)] = event.playerID
            case .press(let decision):
                presses[event.hole] = (player: event.playerID, decision: decision)
            case .clearStrokes:
                strokes.removeValue(forKey: HolePlayer(hole: event.hole, player: event.playerID))
            case .clearHoleEvent(let kind):
                events.removeValue(forKey: HoleEventKey(hole: event.hole, kind: kind))
            }
        }

        self.strokesByHolePlayer = strokes
        self.wolfByHole = wolf
        self.holeEvents = events
        self.pressesByHole = presses
    }

    // MARK: - Scores

    public func gross(hole: Int, player: UUID) -> Int? {
        strokesByHolePlayer[HolePlayer(hole: hole, player: player)]
    }

    public func strokesReceived(hole: Int, player: UUID) -> Int {
        guard let playingHandicap = playingHandicaps[player],
              let strokeIndex = course.hole(hole)?.strokeIndex else { return 0 }
        return HandicapAllocation.strokesReceived(
            courseHandicap: playingHandicap,
            strokeIndex: strokeIndex
        )
    }

    /// The playing handicap this seat ends up with after allowance, cap and mode — the number the
    /// setup screen shows as "gets N strokes".
    public func playingHandicap(for player: UUID) -> Int {
        playingHandicaps[player] ?? 0
    }

    public func net(hole: Int, player: UUID) -> Int? {
        guard let gross = gross(hole: hole, player: player) else { return nil }
        return gross - strokesReceived(hole: hole, player: player)
    }

    // MARK: - Non-stroke inputs

    public func wolfDeclaration(hole: Int) -> (wolf: UUID, declaration: WolfDeclaration)? {
        wolfByHole[hole]
    }

    /// How the group answered the press offered on this hole, if they answered at all.
    public func press(hole: Int) -> (player: UUID, decision: PressDecision)? {
        pressesByHole[hole]
    }

    public func holeEventWinner(hole: Int, kind: HoleEventKind) -> UUID? {
        guard let winner = holeEvents[HoleEventKey(hole: hole, kind: kind)], seats.contains(where: { $0.playerID == winner }) else { return nil }
        return winner
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

    /// The hole the group is on: the first one in the segment that isn't finished, or the segment's
    /// last hole once everything is scored.
    ///
    /// Deliberately "first incomplete" rather than "last complete plus one", so a hole that was
    /// skipped and come back to is what you land on. It shares `isComplete(hole:)` with the "thru
    /// N" count on the in-progress card, so the card and the scorecard can never disagree about
    /// where the round has got to.
    public func currentHole(in segment: RoundSegment) -> Int {
        let holes = (1...18).filter { segment.contains(hole: $0) }
        return holes.first { !isComplete(hole: $0) } ?? holes.last ?? 1
    }

    // MARK: - Helpers for engines

    /// Seats sorted by net score on a hole, lowest first. Only complete holes should be passed.
    func seatsRankedByNet(hole: Int) -> [(seat: Seat, net: Int)] {
        seats
            .compactMap { seat in net(hole: hole, player: seat.playerID).map { (seat, $0) } }
            .sorted { $0.1 < $1.1 }
    }
}
