import Foundation

public struct BestBallConfig: Equatable, Sendable, Codable {
    public let unitStake: Decimal
    /// Seat positions belonging to Team A. The remaining seats form Team B.
    public let teamASeatPositions: Set<Int>

    public init(unitStake: Decimal, teamASeatPositions: Set<Int> = [0, 1]) {
        self.unitStake = unitStake
        self.teamASeatPositions = teamASeatPositions
    }
}

/// Two teams of two compare their lowest net score on each hole.
public enum BestBallEngine: GameDescriptor {
    public static let gameType: GameType = .bestBall
    public static let displayName = "Best Ball"
    public static let summary = "Two teams of two use the lower net score from each team on every hole."
    public static let rules = """
    Best Ball is a two-person team game. Each player plays their own ball, and the team's lower net score counts on each hole.

    The team that wins more holes wins one unit from each player on the other team for every hole won. Tied holes are carried as halves and pay nothing.
    """
    public static let iconName = "person.3.fill"
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 4...4

    public enum SettleError: Error, Equatable, Sendable { case requiresFourPlayers; case teamsMustBeTwoAndTwo }

    public static func settle(state: RoundState, config: BestBallConfig) throws -> Settlement {
        guard state.seats.count == 4 else { throw SettleError.requiresFourPlayers }
        guard config.teamASeatPositions.count == 2, config.teamASeatPositions.allSatisfy({ (0..<4).contains($0) }) else {
            throw SettleError.teamsMustBeTwoAndTwo
        }
        let teamA = state.seats.enumerated().filter { config.teamASeatPositions.contains($0.offset) }.map(\.element)
        let teamB = state.seats.enumerated().filter { !config.teamASeatPositions.contains($0.offset) }.map(\.element)
        var winsA = 0, winsB = 0
        var explanations: [HoleExplanation] = []
        for hole in state.completedHoles(in: state.segment) {
            let a = teamA.compactMap { state.net(hole: hole, player: $0.playerID) }.min()!
            let b = teamB.compactMap { state.net(hole: hole, player: $0.playerID) }.min()!
            if a < b { winsA += 1 } else if b < a { winsB += 1 }
            explanations.append(HoleExplanation(hole: hole, text: "Hole \(hole): " + (a == b ? "halved." : (a < b ? "Team A wins." : "Team B wins."))))
        }
        let standings = state.seats.enumerated().map { index, seat in
            // Each hole is a one-unit team bet, so the final settlement is the
            // hole-win differential multiplied by the unit stake.
            let teamMoney = config.unitStake * Decimal(winsA - winsB)
            let isA = config.teamASeatPositions.contains(index)
            return PlayerStanding(playerID: seat.playerID, points: isA ? winsA : winsB, money: isA ? teamMoney : -teamMoney)
        }
        return Settlement(gameType: gameType, standings: standings, holeExplanations: explanations)
    }
}
