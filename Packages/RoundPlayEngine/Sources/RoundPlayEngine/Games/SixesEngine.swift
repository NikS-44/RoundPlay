import Foundation

public struct SixesConfig: Equatable, Sendable, Codable {
    public let unitStake: Decimal

    public init(unitStake: Decimal) {
        self.unitStake = unitStake
    }
}

/// A foursome split into two-person teams that swap partners every six holes — the format
/// golfers call "Sixes": everyone ends up partnered with, and playing against, everyone else
/// exactly once over 18 holes.
public enum SixesEngine: GameDescriptor {
    public static let gameType: GameType = .sixes
    public static let displayName = "Sixes"
    public static let summary = "A foursome swaps partners every six holes — everyone teams up with everyone else once."
    public static let rules = """
    Sixes is Best Ball played in three six-hole segments, with a different partner each time. The 1st and 2nd seats play the 3rd and 4th on holes 1–6, the 1st and 3rd play the 2nd and 4th on holes 7–12, and the 1st and 4th play the 2nd and 3rd on holes 13–18 — over a full round, everyone in the foursome partners with everyone else exactly once.

    Each player plays their own ball, and the team's lower net score counts on every hole. The team that wins a hole earns one unit from each player on the other team; a halved hole pays nothing.
    """
    public static let iconName = "arrow.triangle.2.circlepath"
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 4...4

    public enum SettleError: Error, Equatable, Sendable { case requiresFourPlayers }

    /// The three ways a foursome's seat positions split into two pairs, one per six-hole
    /// segment. Fixed order, not configurable — the whole point is nobody picks partners.
    static let pairings: [(teamA: Set<Int>, teamB: Set<Int>)] = [
        (teamA: [0, 1], teamB: [2, 3]),
        (teamA: [0, 2], teamB: [1, 3]),
        (teamA: [0, 3], teamB: [1, 2]),
    ]

    /// The pairing in effect for a given hole. Keyed to the hole's absolute number rather than
    /// its position within the round's segment, so a front-nine-only round still starts the
    /// second pairing at hole 7 instead of restarting the rotation at hole 1.
    public static func teams(forHole hole: Int) -> (teamA: Set<Int>, teamB: Set<Int>) {
        pairings[((hole - 1) / 6) % pairings.count]
    }

    public static func settle(state: RoundState, config: SixesConfig) throws -> Settlement {
        guard state.seats.count == 4 else { throw SettleError.requiresFourPlayers }
        var moneyByPosition = [Decimal](repeating: 0, count: 4)
        var pointsByPosition = [Int](repeating: 0, count: 4)
        var explanations: [HoleExplanation] = []

        for hole in state.completedHoles(in: state.segment) {
            let (teamAPositions, teamBPositions) = teams(forHole: hole)
            let teamA = state.seats.enumerated().filter { teamAPositions.contains($0.offset) }.map(\.element)
            let teamB = state.seats.enumerated().filter { teamBPositions.contains($0.offset) }.map(\.element)
            let a = teamA.compactMap { state.net(hole: hole, player: $0.playerID) }.min()!
            let b = teamB.compactMap { state.net(hole: hole, player: $0.playerID) }.min()!

            let winners: Set<Int>? = a < b ? teamAPositions : (b < a ? teamBPositions : nil)
            if let winners {
                let losers = winners == teamAPositions ? teamBPositions : teamAPositions
                for position in winners {
                    moneyByPosition[position] += config.unitStake
                    pointsByPosition[position] += 1
                }
                for position in losers { moneyByPosition[position] -= config.unitStake }
            }
            explanations.append(HoleExplanation(
                hole: hole,
                text: "Hole \(hole): " + (winners.map { "\(names(for: $0, in: state.seats)) win." } ?? "halved.")
            ))
        }

        let standings = state.seats.enumerated().map { index, seat in
            PlayerStanding(playerID: seat.playerID, points: pointsByPosition[index], money: moneyByPosition[index])
        }
        return Settlement(gameType: gameType, standings: standings, holeExplanations: explanations)
    }

    /// Named per hole rather than "Team A"/"Team B" — those letters mean a different pair of
    /// people on every segment, which reads as a mistake in a log meant to end an argument.
    private static func names(for positions: Set<Int>, in seats: [Seat]) -> String {
        seats.enumerated().filter { positions.contains($0.offset) }.map(\.element.name).joined(separator: " & ")
    }
}
