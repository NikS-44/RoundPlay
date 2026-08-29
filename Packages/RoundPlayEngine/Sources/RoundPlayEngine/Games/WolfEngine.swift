import Foundation

/// What happens on holes 17–18 when four players cannot divide 18 evenly.
public enum WolfTailHoleRule: String, Equatable, Sendable, Codable {
    /// Rotation simply continues; seats 1 and 2 get a fifth turn. Simplest, and what most groups do.
    case rotationContinues
    /// Wolf ends after hole 16 and the last two holes score nothing.
    case stopAfter16
}

public struct WolfConfig: Equatable, Sendable, Codable {
    public let unitStake: Decimal
    /// Points to the Wolf and partner when their better ball wins.
    public let partnerWinPoints: Int
    /// Points to each field player when the field wins against a Wolf pair.
    public let fieldWinPoints: Int
    /// Points to a Lone Wolf who beats the whole field.
    public let loneWolfWinPoints: Int
    /// Points to each opponent when a Lone Wolf loses.
    public let loneWolfLossPoints: Int
    public let tailHoleRule: WolfTailHoleRule

    public init(
        unitStake: Decimal,
        partnerWinPoints: Int,
        fieldWinPoints: Int,
        loneWolfWinPoints: Int,
        loneWolfLossPoints: Int,
        tailHoleRule: WolfTailHoleRule
    ) {
        self.unitStake = unitStake
        self.partnerWinPoints = partnerWinPoints
        self.fieldWinPoints = fieldWinPoints
        self.loneWolfWinPoints = loneWolfWinPoints
        self.loneWolfLossPoints = loneWolfLossPoints
        self.tailHoleRule = tailHoleRule
    }

    /// The commonest ruleset. Variants are everywhere, which is exactly why these are config.
    public static func standard(unitStake: Decimal) -> WolfConfig {
        WolfConfig(
            unitStake: unitStake,
            partnerWinPoints: 1,
            fieldWinPoints: 1,
            loneWolfWinPoints: 4,
            loneWolfLossPoints: 1,
            tailHoleRule: .rotationContinues
        )
    }
}

/// Wolf: the tee order rotates, and each hole's Wolf either picks a partner or takes on everyone.
///
/// The only game in the library needing a mid-hole decision, which is why it declares
/// `.partnerChoice` — the scorecard grows a partner picker before scores are entered. A hole with
/// no declaration recorded is skipped rather than guessed at.
public enum WolfEngine: GameDescriptor {
    public static let gameType: GameType = .wolf
    public static let displayName = "Wolf"
    public static let summary = "Take turns being the Wolf. Pick a partner off the tee, or take on all three alone for quadruple points."
    public static let rules = """
    Each hole has a Wolf, rotating through the group in tee order. After watching everyone else's tee shot, the Wolf either picks a partner for that hole (the two of you play your better ball against the other two's better ball) or goes it alone as a Lone Wolf against the whole field.

    A partnered win splits the points between the Wolf and their partner; a field win against them splits points among the other three. Go Lone Wolf and win, and you take quadruple points solo, but lose and each opponent scores against you too. It's the highest-risk, highest-reward call in the round.

    Needs three, four, or five players. With four, the rotation doesn't divide evenly into 18 holes, so seats one and two simply get a fifth turn as Wolf.
    """
    public static let iconName = "pawprint.fill"
    public static let requiredInputs: Set<InputKind> = [.strokes, .partnerChoice]
    public static let playerRange = 3...5

    /// Whose turn it is to be Wolf. Rotates in seat order, wrapping every `seats.count` holes.
    public static func wolf(forHole hole: Int, seats: [Seat]) -> Seat {
        seats[(hole - 1) % seats.count]
    }

    public static func settle(state: RoundState, config: WolfConfig) -> Settlement {
        var points: [UUID: Int] = [:]
        for seat in state.seats { points[seat.playerID] = 0 }
        var explanations: [HoleExplanation] = []

        for hole in state.completedHoles(in: state.segment) {
            if config.tailHoleRule == .stopAfter16 && hole > 16 { continue }
            guard let declared = state.wolfDeclaration(hole: hole) else { continue }

            let wolfSeat = wolf(forHole: hole, seats: state.seats)
            // Trust the seat rotation over the event's player id — the rotation is the rule.
            guard declared.wolf == wolfSeat.playerID else { continue }

            let wolfTeam: [UUID]
            switch declared.declaration {
            case .partner(let partner): wolfTeam = [wolfSeat.playerID, partner]
            case .lone: wolfTeam = [wolfSeat.playerID]
            }
            let field = state.seats.map(\.playerID).filter { !wolfTeam.contains($0) }

            guard let wolfBall = betterBall(state: state, hole: hole, team: wolfTeam),
                  let fieldBall = betterBall(state: state, hole: hole, team: field) else { continue }

            if wolfBall == fieldBall {
                explanations.append(HoleExplanation(
                    hole: hole, text: "Hole \(hole): halved at net \(wolfBall). No points."
                ))
                continue
            }

            let isLone = wolfTeam.count == 1
            let wolfWon = wolfBall < fieldBall
            let text: String

            if wolfWon {
                let award = isLone ? config.loneWolfWinPoints : config.partnerWinPoints
                for player in wolfTeam { points[player, default: 0] += award }
                text = isLone
                    ? "Hole \(hole): \(wolfSeat.name) went Lone Wolf and won. \(award) points."
                    : "Hole \(hole): \(names(wolfTeam, in: state)) win the hole. \(award) point each."
            } else {
                let award = isLone ? config.loneWolfLossPoints : config.fieldWinPoints
                for player in field { points[player, default: 0] += award }
                text = isLone
                    ? "Hole \(hole): \(wolfSeat.name)'s Lone Wolf failed. \(award) point to each opponent."
                    : "Hole \(hole): \(names(field, in: state)) take the hole. \(award) point each."
            }

            explanations.append(HoleExplanation(hole: hole, text: text))
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

    /// Lowest net on the team — better ball, not combined.
    private static func betterBall(state: RoundState, hole: Int, team: [UUID]) -> Int? {
        team.compactMap { state.net(hole: hole, player: $0) }.min()
    }

    private static func names(_ ids: [UUID], in state: RoundState) -> String {
        ids.compactMap { id in state.seats.first { $0.playerID == id }?.name }
            .joined(separator: " and ")
    }
}
