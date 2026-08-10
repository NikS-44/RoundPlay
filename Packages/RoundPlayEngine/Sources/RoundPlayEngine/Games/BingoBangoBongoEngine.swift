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
    public static let rules = """
    Three points are up for grabs on every hole, and none of them care about your handicap: Bingo goes to whoever is first to get their ball on the green, Bango to whoever's ball ends up closest to the pin once everyone's on, and Bongo to whoever holes out first.

    Because it rewards being first rather than being good, it's the strongest equalizer in the library — a 25-handicapper who reaches the green first takes the bingo from a scratch player every time.

    It only works if the group actually plays in the traditional order (farthest from the hole plays first), since that's what makes "first on the green" meaningful. The app can't enforce that — it's recorded on the honor system by whoever's keeping score. Works for two to four players.
    """
    public static let iconName = "star.circle.fill"
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
