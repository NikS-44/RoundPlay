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
