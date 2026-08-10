import Foundation

public struct SkinsConfig: Equatable, Sendable, Codable {
    /// Value of one skin, per opponent.
    public let unitStake: Decimal
    /// When true (the default and near-universal rule), a tied hole rolls its skin forward.
    public let carryOverTies: Bool

    public init(unitStake: Decimal, carryOverTies: Bool = true) {
        self.unitStake = unitStake
        self.carryOverTies = carryOverTies
    }
}

/// Skins: each hole is worth one skin, won outright by the lowest net score.
///
/// Ties carry the pot forward, which is what produces the big swings late in a round. Skins left
/// unclaimed when the round ends are **not** paid — the money was never won. Groups that prefer
/// to split the leftover do so in cash at the bar; encoding it here would mean inventing a rule
/// the group did not agree to.
public enum SkinsEngine: GameDescriptor {
    public static let gameType: GameType = .skins
    public static let displayName = "Skins"
    public static let summary = "Every hole is worth a skin. Win the hole outright to take it — tie and it rolls over."
    public static let rules = """
    Every hole is worth one skin. Whoever posts the lowest net score on a hole wins that skin outright — the whole group pays them for it.

    Tie the low score and nobody wins: the skin carries over and stacks onto the next hole. A carried skin can keep growing for several holes before someone finally wins it clean, which is what produces the big swings late in a round.

    Any skins still unclaimed when the round ends are simply not paid — that money was never won by anyone. Groups that want to split the leftover do it in cash at the bar; RoundPlay won't invent a rule your group didn't agree to.
    """
    public static let iconName = "dollarsign.circle.fill"
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 2...8

    public static func settle(state: RoundState, config: SkinsConfig) -> Settlement {
        var skinsWon: [UUID: Int] = [:]
        var explanations: [HoleExplanation] = []
        var carried = 0

        for hole in state.completedHoles(in: state.segment) {
            let ranked = state.seatsRankedByNet(hole: hole)
            guard let best = ranked.first else { continue }

            let atBest = ranked.filter { $0.net == best.net }
            let potThisHole = carried + 1

            if atBest.count == 1 || !config.carryOverTies {
                let winner = atBest[0].seat
                skinsWon[winner.playerID, default: 0] += potThisHole
                carried = 0

                let plural = potThisHole == 1 ? "skin" : "skins"
                let value = config.unitStake * Decimal(potThisHole)
                    * Decimal(max(state.seats.count - 1, 0))
                let carryNote = potThisHole > 1 ? " — carryover from earlier" : ""
                explanations.append(HoleExplanation(
                    hole: hole,
                    text: "Hole \(hole): \(winner.name) wins \(potThisHole) \(plural) "
                        + "(\(formatted(value)))\(carryNote)."
                ))
            } else {
                carried = potThisHole
                let names = atBest.map(\.seat.name).joined(separator: " and ")
                explanations.append(HoleExplanation(
                    hole: hole,
                    text: "Hole \(hole): \(names) tied at net \(best.net). "
                        + "\(potThisHole) carries to the next hole."
                ))
            }
        }

        // Each skin is collected from every other player at the unit stake.
        let opponents = Decimal(max(state.seats.count - 1, 0))
        let totalSkins = skinsWon.values.reduce(0, +)

        let standings = state.seats.map { seat -> PlayerStanding in
            let won = skinsWon[seat.playerID] ?? 0
            let collected = config.unitStake * Decimal(won) * opponents
            let paid = config.unitStake * Decimal(totalSkins - won)
            return PlayerStanding(
                playerID: seat.playerID,
                points: won,
                money: collected - paid
            )
        }

        return Settlement(
            gameType: gameType,
            standings: standings,
            holeExplanations: explanations
        )
    }

    private static func formatted(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}
