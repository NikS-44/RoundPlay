import Foundation

public struct NassauConfig: Equatable, Sendable, Codable {
    /// Paid per bet won. A $10 Nassau risks $30 before any press.
    public let unitStake: Decimal
    /// Holes down at which a press is offered. `nil` disables presses entirely.
    /// Two is the near-universal convention where presses are played at all.
    ///
    /// Offered, not opened: falling this far behind puts the question to the group, and the bet
    /// only exists once somebody says yes. See `PressDecision`.
    public let pressAt: Int?

    /// Stored rounds encoded this as `automaticPressAt` back when the press opened itself, so the
    /// key outlives the name. Renaming the key would silently drop the threshold from every round
    /// already on disk and quietly turn presses off in them.
    private enum CodingKeys: String, CodingKey {
        case unitStake
        case pressAt = "automaticPressAt"
    }

    public init(unitStake: Decimal, pressAt: Int? = 2) {
        self.unitStake = unitStake
        self.pressAt = pressAt
    }
}

/// Nassau: three match-play bets in one round — front nine, back nine, and the full eighteen.
///
/// The defining feature is the **press**: a side that falls behind opens a fresh bet on the
/// remaining holes, so a blowout front nine still has money live on it. Presses are what make a
/// $10 Nassau routinely settle for $40, and getting them wrong is the fastest way to lose a
/// user's trust.
///
/// A press is offered, never assumed. `pressOffer(state:config:)` reports the question standing
/// right now — the scorecard puts it to the group before the next hole — and `settle` counts only
/// the presses somebody actually took. Nothing here writes events; the answer arrives back in the
/// log as a `.press` event like any other entry.
///
/// Phase 1 is singles only. The 2v2 best-ball variant needs team assignment that the Phase 1b UI
/// does not collect.
public enum NassauEngine: GameDescriptor {
    public static let gameType: GameType = .nassau
    public static let displayName = "Nassau"
    public static let summary = "Three matches in one round: front nine, back nine, and overall. Fall behind and you can press."
    public static let rules = """
    Nassau is three separate match-play bets in one round: who wins the front nine, who wins the back nine, and who wins the full eighteen. Each is worth the stake on its own, so a $10 Nassau has $30 riding on it before anything else happens.

    The bet that makes Nassau interesting is the press: if you fall far enough behind on a nine, you can open a brand-new bet on just the holes that are left, effectively doubling down to claw back. That's how a $10 Nassau routinely settles for $40 or more.

    Go two down and we'll ask, before you tee off on the next hole, whether you want to press. Say no and we won't ask again until you're further behind. Nothing is added to the card unless you take it.

    This is a two-player game. Phase 1 doesn't support the 2v2 best-ball team version, which needs its own partner assignment.
    """
    public static let iconName = "flag.checkered.2.crossed"
    public static let requiredInputs: Set<InputKind> = [.strokes]
    public static let playerRange = 2...2

    public enum SettleError: Error, Equatable, Sendable {
        case requiresTwoPlayers
    }

    /// A press the group has not answered yet: who is down, by how much, and what it would cost.
    ///
    /// Carries everything the prompt needs to write a sentence, so the scorecard never has to know
    /// how a Nassau is scored to ask the question.
    public struct PressOffer: Equatable, Sendable {
        /// The hole the new bet would start on — always the next one, never one already played.
        public let hole: Int
        /// The last hole of the nine the press runs to.
        public let throughHole: Int
        public let segment: RoundSegment
        /// The side that is down and has the call.
        public let trailingPlayerID: UUID
        public let leadingPlayerID: UUID
        public let holesDown: Int
        /// What the new bet is worth if taken — the same unit as every other Nassau bet.
        public let stake: Decimal

        public init(
            hole: Int,
            throughHole: Int,
            segment: RoundSegment,
            trailingPlayerID: UUID,
            leadingPlayerID: UUID,
            holesDown: Int,
            stake: Decimal
        ) {
            self.hole = hole
            self.throughHole = throughHole
            self.segment = segment
            self.trailingPlayerID = trailingPlayerID
            self.leadingPlayerID = leadingPlayerID
            self.holesDown = holesDown
            self.stake = stake
        }
    }

    /// One live match-play bet over a range of holes.
    private struct Bet {
        let segment: RoundSegment
        let startHole: Int
        let isPress: Bool
        var holesUp = 0      // positive means the first seat is up
    }

    private struct Replay {
        var bets: [Bet]
        var explanations: [HoleExplanation]
        var offer: PressOffer?
    }

    public static func settle(state: RoundState, config: NassauConfig) throws -> Settlement {
        guard state.seats.count == 2 else { throw SettleError.requiresTwoPlayers }
        let first = state.seats[0], second = state.seats[1]
        let replayed = replay(state: state, config: config)

        var firstMoney = Decimal(0)
        for bet in replayed.bets where bet.holesUp != 0 {
            firstMoney += bet.holesUp > 0 ? config.unitStake : -config.unitStake
        }

        let standings = [
            PlayerStanding(playerID: first.playerID,
                           points: replayed.bets.reduce(0) { $0 + $1.holesUp },
                           money: firstMoney),
            PlayerStanding(playerID: second.playerID,
                           points: -replayed.bets.reduce(0) { $0 + $1.holesUp },
                           money: -firstMoney)
        ]

        return Settlement(gameType: gameType, standings: standings,
                          holeExplanations: replayed.explanations)
    }

    /// The press question standing right now, or `nil` when there is nothing to ask.
    ///
    /// Pure, like everything else here: the scorecard calls this every time the round's state
    /// changes rather than being told when a press becomes available.
    public static func pressOffer(state: RoundState, config: NassauConfig) -> PressOffer? {
        guard state.seats.count == 2 else { return nil }
        return replay(state: state, config: config).offer
    }

    // MARK: - Replay

    /// Walks the completed holes once and reports everything that depends on that walk: where the
    /// bets stand, the hole-by-hole narration, and the one press question still unanswered.
    ///
    /// `settle` and `pressOffer` both read from this so the bet the group is offered and the bet
    /// they end up paying can never disagree.
    private static func replay(state: RoundState, config: NassauConfig) -> Replay {
        let first = state.seats[0], second = state.seats[1]

        let segments: [RoundSegment] = state.segment == .total ? RoundSegment.allCases : [state.segment]
        var bets: [Bet] = segments.map {
            Bet(segment: $0, startHole: $0 == .back ? 10 : 1, isPress: false)
        }
        var explanations: [HoleExplanation] = []
        /// The deepest deficit each nine has already put to the group. A no at two down doesn't
        /// silence the question at three down — but it does stop it being asked again at two.
        var answered: [RoundSegment: Int] = [:]
        var offer: PressOffer?

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

            // Presses are offered *after* the hole is scored, on the remaining holes of that nine.
            // Only the last completed hole can leave a question standing, so the offer is cleared
            // on the way in: a press nobody answered before playing on is a press that lapsed.
            offer = nil
            guard let trigger = config.pressAt else { continue }

            let nextHole = hole + 1
            for bet in bets where !bet.isPress && bet.segment != .total
                && bet.segment.contains(hole: hole) {
                let deficit = abs(bet.holesUp)
                guard deficit >= trigger,
                      bet.segment.contains(hole: nextHole),
                      deficit > (answered[bet.segment] ?? 0)
                else { continue }

                let trailing = bet.holesUp > 0 ? second : first
                let leading = bet.holesUp > 0 ? first : second

                if let recorded = state.press(hole: nextHole) {
                    answered[bet.segment] = deficit
                    switch recorded.decision {
                    case .accepted:
                        // Honoured on the strength of the answer, not of the current deficit. A
                        // score corrected later can move the numbers underneath it; the bet the
                        // group shook on still stands.
                        bets.append(Bet(segment: bet.segment, startHole: nextHole, isPress: true))
                        explanations.append(HoleExplanation(
                            hole: hole,
                            text: "\(trailing.name) was \(deficit) down on the "
                                + "\(bet.segment.displayName) and pressed. New bet on holes "
                                + "\(nextHole)–\(lastHole(of: bet.segment))."
                        ))
                    case .declined:
                        explanations.append(HoleExplanation(
                            hole: hole,
                            text: "\(trailing.name) was \(deficit) down on the "
                                + "\(bet.segment.displayName) and passed on the press."
                        ))
                    }
                } else if state.isComplete(hole: nextHole) {
                    // They played on without answering. Treated as a pass so the question doesn't
                    // follow them down the fairway; falling further behind asks it again.
                    answered[bet.segment] = deficit
                } else {
                    offer = PressOffer(
                        hole: nextHole,
                        throughHole: lastHole(of: bet.segment),
                        segment: bet.segment,
                        trailingPlayerID: trailing.playerID,
                        leadingPlayerID: leading.playerID,
                        holesDown: deficit,
                        stake: config.unitStake
                    )
                }
            }
        }

        return Replay(bets: bets, explanations: explanations, offer: offer)
    }

    private static func lastHole(of segment: RoundSegment) -> Int {
        segment == .front ? 9 : 18
    }
}
