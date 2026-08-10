import Foundation

public enum StrokePlayScoreType: String, Equatable, Sendable, Codable {
    case gross
    case net
}

public struct StrokePlayConfig: Equatable, Sendable, Codable {
    public let scoreType: StrokePlayScoreType

    public init(scoreType: StrokePlayScoreType = .net) {
        self.scoreType = scoreType
    }
}

/// Ordinary stroke play: the lowest completed-round total wins.
public enum StrokePlayEngine: GameDescriptor {
    public static let gameType: GameType = .strokePlay
    public static let displayName = "Stroke Play"
    public static let summary = "The lowest total gross or net score after the round wins."
    public static let rules = """
    Stroke Play is the standard golf format. Add each player's score across the holes played; the lowest total wins.

    Choose gross to compare the strokes actually taken, or net to subtract the casual handicap strokes shown on the scorecard. No side bet is attached by default.
    """
    public static let iconName = "number.circle.fill"
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 2...8

    public static func settle(state: RoundState, config: StrokePlayConfig) -> Settlement {
        let holes = state.completedHoles(in: state.segment)
        let standings = state.seats.map { seat in
            let total = holes.reduce(0) { total, hole in
                total + (config.scoreType == .gross
                    ? (state.gross(hole: hole, player: seat.playerID) ?? 0)
                    : (state.net(hole: hole, player: seat.playerID) ?? 0))
            }
            return PlayerStanding(playerID: seat.playerID, points: total, money: 0)
        }
        let explanations = holes.map { hole in
            let scores = state.seats.map { seat in
                let score = config.scoreType == .gross
                    ? (state.gross(hole: hole, player: seat.playerID) ?? 0)
                    : (state.net(hole: hole, player: seat.playerID) ?? 0)
                return "\(seat.name) \(score)"
            }.joined(separator: ", ")
            return HoleExplanation(hole: hole, text: "Hole \(hole): \(scores).")
        }
        return Settlement(gameType: gameType, standings: standings, holeExplanations: explanations)
    }
}
