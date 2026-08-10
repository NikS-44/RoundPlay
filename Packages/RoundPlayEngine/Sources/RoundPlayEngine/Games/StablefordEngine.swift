import Foundation

/// Maps a net score relative to par onto points.
///
/// Stored as explicit boundaries rather than a formula because the variants genuinely differ in
/// shape: standard floors at zero, Modified goes negative. A group that plays its own table gets
/// it by constructing one, not by us adding a case.
public struct StablefordPointsTable: Equatable, Sendable, Codable {
    /// Points for each net-relative-to-par value, best first.
    /// Index 0 is albatross (−3), 1 eagle (−2), 2 birdie (−1), 3 par (0), 4 bogey (+1), 5 double (+2).
    public let byRelativeScore: [Int: Int]
    /// Applied to anything worse than the worst listed entry.
    public let floorPoints: Int

    public init(byRelativeScore: [Int: Int], floorPoints: Int) {
        self.byRelativeScore = byRelativeScore
        self.floorPoints = floorPoints
    }

    public func points(netRelativeToPar: Int) -> Int {
        if let exact = byRelativeScore[netRelativeToPar] { return exact }
        // Better than the best listed entry scores the best listed value; worse hits the floor.
        guard let best = byRelativeScore.keys.min(), let worst = byRelativeScore.keys.max() else {
            return floorPoints
        }
        if netRelativeToPar < best { return byRelativeScore[best] ?? floorPoints }
        if netRelativeToPar > worst { return floorPoints }
        return floorPoints
    }

    /// Bogey 1, par 2, birdie 3, eagle 4, albatross 5; double bogey or worse scores nothing.
    public static let standard = StablefordPointsTable(
        byRelativeScore: [-3: 5, -2: 4, -1: 3, 0: 2, 1: 1, 2: 0],
        floorPoints: 0
    )

    /// The tour variant: eagle 5, birdie 2, par 0, bogey −1, double or worse −3.
    public static let modified = StablefordPointsTable(
        byRelativeScore: [-3: 8, -2: 5, -1: 2, 0: 0, 1: -1, 2: -3],
        floorPoints: -3
    )
}

public struct StablefordConfig: Equatable, Sendable, Codable {
    public let unitStake: Decimal
    public let pointsTable: StablefordPointsTable

    public init(unitStake: Decimal, pointsTable: StablefordPointsTable = .standard) {
        self.unitStake = unitStake
        self.pointsTable = pointsTable
    }

    public static let standard = StablefordConfig(unitStake: 1, pointsTable: .standard)
    public static let modified = StablefordConfig(unitStake: 1, pointsTable: .modified)
}

/// Stableford: points against net par, so one disastrous hole costs a point rather than the round.
///
/// This is the reason it is the best format in the library for beginners and for mixed-skill
/// groups — a blowup floors at zero instead of compounding.
public enum StablefordEngine: GameDescriptor {
    public static let gameType: GameType = .stableford
    public static let displayName = "Stableford"
    public static let summary = "Score points per hole instead of counting strokes. A bad hole costs you a point, not your round."
    public static let rules = """
    Instead of adding up every stroke, each hole earns you points based on your net score against par: the standard table pays 2 for par, 3 for birdie, 4 for eagle, 5 for albatross, and 1 for bogey — anything worse than bogey scores zero.

    That floor is the whole point. A single disaster hole costs you one point, not the ten strokes it actually took, so one blowup can't sink your whole round the way it would in stroke play. Highest total points at the end wins.

    Works for any group size from two up to eight, and pairs well with a per-point stake so the money tracks the same points everyone's already watching.
    """
    public static let iconName = "chart.bar.fill"
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 2...8

    public static func settle(state: RoundState, config: StablefordConfig) -> Settlement {
        var points: [UUID: Int] = [:]
        for seat in state.seats { points[seat.playerID] = 0 }
        var explanations: [HoleExplanation] = []

        for hole in state.completedHoles(in: state.segment) {
            guard let par = state.course.hole(hole)?.par else { continue }
            var line: [String] = []

            for seat in state.seats {
                guard let net = state.net(hole: hole, player: seat.playerID) else { continue }
                let earned = config.pointsTable.points(netRelativeToPar: net - par)
                points[seat.playerID, default: 0] += earned
                line.append("\(seat.name) \(earned)")
            }

            explanations.append(HoleExplanation(
                hole: hole,
                text: "Hole \(hole) (par \(par)): " + line.joined(separator: ", ") + "."
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
