import Foundation

/// One player's result in one game.
public struct PlayerStanding: Equatable, Sendable, Codable, Identifiable {
    public let playerID: UUID
    /// Game-native units: skins won, match holes up, Stableford points, Wolf points.
    public let points: Int
    /// Positive means the player collects; negative means they pay.
    public let money: Decimal

    public var id: UUID { playerID }

    public init(playerID: UUID, points: Int, money: Decimal) {
        self.playerID = playerID
        self.points = points
        self.money = money
    }
}

/// A plain-English account of what happened on one hole.
///
/// Every dollar in a settlement must be traceable to one of these. This is the feature that ends
/// the 19th-hole argument, so it is part of the return type rather than a debugging afterthought.
public struct HoleExplanation: Equatable, Sendable, Codable {
    public let hole: Int
    public let text: String

    public init(hole: Int, text: String) {
        self.hole = hole
        self.text = text
    }
}

/// The result of settling one game over one round.
public struct Settlement: Equatable, Sendable, Codable {
    public let gameType: GameType
    public let standings: [PlayerStanding]
    public let holeExplanations: [HoleExplanation]

    public init(
        gameType: GameType,
        standings: [PlayerStanding],
        holeExplanations: [HoleExplanation]
    ) {
        self.gameType = gameType
        self.standings = standings
        self.holeExplanations = holeExplanations
    }

    public func money(for player: UUID) -> Decimal {
        standings.first { $0.playerID == player }?.money ?? 0
    }

    public func points(for player: UUID) -> Int {
        standings.first { $0.playerID == player }?.points ?? 0
    }

    /// Money must net to exactly zero — nobody conjures a dollar and none leaks out.
    /// Asserted in every engine's test suite.
    public var isZeroSum: Bool {
        standings.reduce(Decimal(0)) { $0 + $1.money } == 0
    }

    /// Settles a points-based game where every player pays every other player the unit stake for
    /// each point of difference between them. This is how Nines, Stableford, Wolf, and Bingo Bango
    /// Bongo convert points to money, and it is zero-sum by construction.
    public static func pointDifferenceMoney(
        points: [UUID: Int],
        unitStake: Decimal
    ) -> [UUID: Decimal] {
        var money: [UUID: Decimal] = [:]
        for (player, own) in points {
            let total = points.reduce(0) { partial, other in
                other.key == player ? partial : partial + (own - other.value)
            }
            money[player] = Decimal(total) * unitStake
        }
        return money
    }
}
