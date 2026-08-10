import Foundation

public struct NassauConfig: Equatable, Sendable, Codable {
    /// Paid per bet won. A $10 Nassau risks $30 before any press.
    public let unitStake: Decimal
    /// Holes down that trigger an automatic press. `nil` disables presses entirely.
    /// Two is the near-universal convention where presses are played at all.
    public let automaticPressAt: Int?

    public init(unitStake: Decimal, automaticPressAt: Int? = 2) {
        self.unitStake = unitStake
        self.automaticPressAt = automaticPressAt
    }
}

/// Nassau: three match-play bets in one round — front nine, back nine, and the full eighteen.
///
/// The defining feature is the **press**: a side that falls behind opens a fresh bet on the
/// remaining holes, so a blowout front nine still has money live on it. Presses are what make a
/// $10 Nassau routinely settle for $40, and getting them wrong is the fastest way to lose a
/// user's trust.
///
/// Phase 1 is singles only. The 2v2 best-ball variant needs team assignment that the Phase 1b UI
/// does not collect.
public enum NassauEngine: GameDescriptor {
    public static let gameType: GameType = .nassau
    public static let displayName = "Nassau"
    public static let summary = "Three bets in one round: front nine, back nine, and overall. Fall behind and you can press."
    public static let rules = """
    Nassau is three separate match-play bets in one round: who wins the front nine, who wins the back nine, and who wins the full eighteen. Each is worth the stake on its own, so a $10 Nassau has $30 riding on it before anything else happens.

    The bet that makes Nassau interesting is the press: if you fall far enough behind on the holes remaining in a segment, you can open a brand-new bet on just those remaining holes — effectively doubling down to claw back. That's how a $10 Nassau routinely settles for $40 or more.

    This is a two-player game — Phase 1 doesn't support the 2v2 best-ball team version, which needs its own partner assignment.
    """
    public static let iconName = "flag.checkered.2.crossed"
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 2...2

    public enum SettleError: Error, Equatable, Sendable {
        case requiresTwoPlayers
    }

    /// One live match-play bet over a range of holes.
    private struct Bet {
        let segment: RoundSegment
        let startHole: Int
        let isPress: Bool
        var holesUp = 0      // positive means the first seat is up
    }

    public static func settle(state: RoundState, config: NassauConfig) throws -> Settlement {
        guard state.seats.count == 2 else { throw SettleError.requiresTwoPlayers }
        let first = state.seats[0], second = state.seats[1]

        let segments: [RoundSegment] = state.segment == .total ? RoundSegment.allCases : [state.segment]
        var bets: [Bet] = segments.map {
            Bet(segment: $0, startHole: $0 == .back ? 10 : 1, isPress: false)
        }
        var explanations: [HoleExplanation] = []

        for hole in state.completedHoles(in: state.segment) {
            guard let firstNet = state.net(hole: hole, player: first.playerID),
                  let secondNet = state.net(hole: hole, player: second.playerID) else { continue }

            let delta = firstNet == secondNet ? 0 : (firstNet < secondNet ? 1 : -1)

            for index in bets.indices where bets[index].segment.contains(hole: hole)
                && hole >= bets[index].startHole {
                bets[index].holesUp += delta
            }

            let leader = delta > 0 ? first.name : (delta < 0 ? second.name : nil)
            explanations.append(HoleExplanation(
                hole: hole,
                text: leader.map { "Hole \(hole): \($0) wins the hole." }
                    ?? "Hole \(hole): halved."
            ))

            // Presses open *after* the hole is scored, on the remaining holes of that segment.
            guard let trigger = config.automaticPressAt else { continue }
            for bet in bets where !bet.isPress && bet.segment != .total
                && bet.segment.contains(hole: hole) {
                guard abs(bet.holesUp) >= trigger else { continue }
                let nextHole = hole + 1
                guard bet.segment.contains(hole: nextHole) else { continue }
                let alreadyPressed = bets.contains {
                    $0.isPress && $0.segment == bet.segment && $0.startHole == nextHole
                }
                guard !alreadyPressed else { continue }

                bets.append(Bet(segment: bet.segment, startHole: nextHole, isPress: true))
                let trailing = bet.holesUp > 0 ? second.name : first.name
                explanations.append(HoleExplanation(
                    hole: hole,
                    text: "\(trailing) is \(abs(bet.holesUp)) down on the "
                        + "\(bet.segment.displayName) — press opens on hole \(nextHole)."
                ))
            }
        }

        var firstMoney = Decimal(0)
        for bet in bets where bet.holesUp != 0 {
            firstMoney += bet.holesUp > 0 ? config.unitStake : -config.unitStake
        }

        let standings = [
            PlayerStanding(playerID: first.playerID,
                           points: bets.reduce(0) { $0 + $1.holesUp },
                           money: firstMoney),
            PlayerStanding(playerID: second.playerID,
                           points: -bets.reduce(0) { $0 + $1.holesUp },
                           money: -firstMoney)
        ]

        return Settlement(gameType: gameType, standings: standings, holeExplanations: explanations)
    }
}
