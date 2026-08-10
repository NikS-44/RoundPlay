import Foundation

/// The append-only event log folded into current values.
///
/// This is the single place the log→state reduction happens. Every engine reads `RoundState`
/// and never touches raw events, so "latest sequence wins" is defined exactly once.
public struct RoundState: Sendable {
    public let seats: [Seat]
    public let course: Course
    public let segment: RoundSegment
    public let handicapSettings: HandicapSettings

    /// Playing handicap per player, resolved once at init rather than per `strokesReceived` call —
    /// `offTheLow` depends on every other seat, so recomputing it per hole per player would be
    /// quadratic across a scorecard render.
    private let playingHandicaps: [UUID: Int]

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
            case .clearStrokes:
                strokes.removeValue(forKey: HolePlayer(hole: event.hole, player: event.playerID))
            case .clearHoleEvent(let kind):
                events.removeValue(forKey: HoleEventKey(hole: event.hole, kind: kind))
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

    // MARK: - Helpers for engines

    /// Seats sorted by net score on a hole, lowest first. Only complete holes should be passed.
    func seatsRankedByNet(hole: Int) -> [(seat: Seat, net: Int)] {
        seats
            .compactMap { seat in net(hole: hole, player: seat.playerID).map { (seat, $0) } }
            .sorted { $0.1 < $1.1 }
    }
}
