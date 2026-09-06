import Foundation
import RoundPlayEngine

public enum HoleEntryStep: Equatable, Sendable {
    case partnerChoice
    /// Every player's score, on one screen. This used to be one step *per seat*, which made the
    /// watch a forward-only wizard: the only way back to a score you'd fumbled was to swipe
    /// backwards through everyone entered after it.
    case scores
    case holeEvents
}

public enum HoleEntrySequence {
    public static func steps(requiredInputs: Set<InputKind>) -> [HoleEntryStep] {
        var result: [HoleEntryStep] = []
        if requiredInputs.contains(.partnerChoice) {
            result.append(.partnerChoice)
        }
        if requiredInputs.contains(.strokes) {
            result.append(.scores)
        }
        if requiredInputs.contains(.holeEvents) {
            result.append(.holeEvents)
        }
        return result
    }
}

public enum WatchGameDefaults {
    public static let stakePresets: [Decimal] = [1, 2, 5, 10]

    public static func configuration(for type: GameType, stake: Decimal) -> GameConfiguration {
        switch type {
        case .strokePlay: .strokePlay(StrokePlayConfig())
        case .matchPlay: .matchPlay(MatchPlayConfig(unitStake: stake))
        case .bestBall: .bestBall(BestBallConfig(unitStake: stake))
        case .sixes: .sixes(SixesConfig(unitStake: stake))
        case .skins: .skins(SkinsConfig(unitStake: stake))
        case .nassau: .nassau(NassauConfig(unitStake: stake))
        case .stableford: .stableford(StablefordConfig(unitStake: stake))
        case .nines: .nines(NinesConfig(unitStake: stake))
        case .wolf: .wolf(.standard(unitStake: stake))
        case .bingoBangoBongo: .bingoBangoBongo(BingoBangoBongoConfig(unitStake: stake))
        }
    }
}

public enum PreviousRoundMatch {
    public static func find(playerIDs: Set<UUID>, in rounds: [RoundRecord]) -> RoundRecord? {
        rounds
            .filter { !$0.isDeleted }
            .sorted { $0.startedAt > $1.startedAt }
            .first { Set(($0.seats ?? []).map(\.playerID)) == playerIDs }
    }

    public static func summary(_ round: RoundRecord) -> String {
        let parts = (round.games ?? []).compactMap { game -> String? in
            guard let config = game.configuration else { return nil }
            let name = GameLibrary.metadata(for: config.gameType).displayName
            if config.gameType == .strokePlay { return name }
            return "\(name) $\(config.unitStake)"
        }
        return parts.isEmpty ? "Stroke play" : parts.joined(separator: ", ")
    }
}
