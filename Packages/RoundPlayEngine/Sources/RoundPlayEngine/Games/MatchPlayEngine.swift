import Foundation

public struct MatchPlayConfig: Equatable, Sendable, Codable {
    public let unitStake: Decimal

    public init(unitStake: Decimal) { self.unitStake = unitStake }
}

/// One two-player match over the selected holes. A tied match pays nothing.
public enum MatchPlayEngine: GameDescriptor {
    public static let gameType: GameType = .matchPlay
    public static let displayName = "Match Play"
    public static let summary = "Two players compete hole by hole; whoever wins more holes wins the match."
    public static let rules = """
    Match Play is one head-to-head bet. The lower net score wins each hole, while a tie halves the hole. The player who is up after the selected holes wins the match and the agreed stake.

    This launch version is singles only. It does not use presses or team play.
    """
    public static let iconName = "person.2.fill"
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 2...2

    public enum SettleError: Error, Equatable, Sendable { case requiresTwoPlayers }

    public static func settle(state: RoundState, config: MatchPlayConfig) throws -> Settlement {
        guard state.seats.count == 2 else { throw SettleError.requiresTwoPlayers }
        let first = state.seats[0], second = state.seats[1]
        var up = 0
        var explanations: [HoleExplanation] = []
        for hole in state.completedHoles(in: state.segment) {
            guard let a = state.net(hole: hole, player: first.playerID), let b = state.net(hole: hole, player: second.playerID) else { continue }
            if a < b { up += 1 } else if a > b { up -= 1 }
            let result = a == b ? "halved" : (a < b ? "\(first.name) wins" : "\(second.name) wins")
            explanations.append(HoleExplanation(hole: hole, text: "Hole \(hole): \(result)."))
        }
        let money = up == 0 ? Decimal(0) : (up > 0 ? config.unitStake : -config.unitStake)
        return Settlement(gameType: gameType, standings: [
            PlayerStanding(playerID: first.playerID, points: up, money: money),
            PlayerStanding(playerID: second.playerID, points: -up, money: -money)
        ], holeExplanations: explanations)
    }
}
