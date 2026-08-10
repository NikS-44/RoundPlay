import Foundation

/// A game plus the settings the group agreed on.
public enum GameConfiguration: Equatable, Sendable, Codable {
    case strokePlay(StrokePlayConfig)
    case matchPlay(MatchPlayConfig)
    case bestBall(BestBallConfig)
    case skins(SkinsConfig)
    case nassau(NassauConfig)
    case stableford(StablefordConfig)
    case nines(NinesConfig)
    case wolf(WolfConfig)
    case bingoBangoBongo(BingoBangoBongoConfig)

    public var gameType: GameType {
        switch self {
        case .strokePlay: .strokePlay
        case .matchPlay: .matchPlay
        case .bestBall: .bestBall
        case .skins: .skins
        case .nassau: .nassau
        case .stableford: .stableford
        case .nines: .nines
        case .wolf: .wolf
        case .bingoBangoBongo: .bingoBangoBongo
        }
    }

    /// Every game's config carries a unit stake — surfaced here so the UI can read or re-seed it
    /// without switching on the game type itself.
    public var unitStake: Decimal {
        switch self {
        case .strokePlay: 0
        case .matchPlay(let config): config.unitStake
        case .bestBall(let config): config.unitStake
        case .skins(let config): config.unitStake
        case .nassau(let config): config.unitStake
        case .stableford(let config): config.unitStake
        case .nines(let config): config.unitStake
        case .wolf(let config): config.unitStake
        case .bingoBangoBongo(let config): config.unitStake
        }
    }
}

/// Static facts about a game, for the library screen and the scorecard's input rendering.
public struct GameMetadata: Equatable, Sendable, Identifiable {
    public let gameType: GameType
    public let displayName: String
    public let summary: String
    public let rules: String
    public let iconName: String
    public let requiredInputs: Set<InputKind>
    public let playerRange: ClosedRange<Int>

    public var id: GameType { gameType }

    /// "2–8 players", "3 players", "4 players" — for the library card.
    public var playerCountLabel: String {
        playerRange.lowerBound == playerRange.upperBound
            ? "\(playerRange.lowerBound) players"
            : "\(playerRange.lowerBound)–\(playerRange.upperBound) players"
    }
}

/// The single entry point the app uses to settle any game.
///
/// The UI never imports an engine directly and never switches on `GameType` — adding a seventh
/// game means adding a case here and nothing else changes.
public enum GameLibrary {

    public enum LibraryError: Error, Equatable, Sendable {
        case unsupportedPlayerCount(gameType: GameType, count: Int)
    }

    public static var all: [GameMetadata] {
        GameType.allCases.map(metadata(for:))
    }

    public static func metadata(for gameType: GameType) -> GameMetadata {
        switch gameType {
        case .strokePlay: describe(StrokePlayEngine.self)
        case .matchPlay: describe(MatchPlayEngine.self)
        case .bestBall: describe(BestBallEngine.self)
        case .skins: describe(SkinsEngine.self)
        case .nassau: describe(NassauEngine.self)
        case .stableford: describe(StablefordEngine.self)
        case .nines: describe(NinesEngine.self)
        case .wolf: describe(WolfEngine.self)
        case .bingoBangoBongo: describe(BingoBangoBongoEngine.self)
        }
    }

    public static func settle(
        _ configuration: GameConfiguration,
        state: RoundState
    ) throws -> Settlement {
        let meta = metadata(for: configuration.gameType)
        guard meta.playerRange.contains(state.seats.count) else {
            throw LibraryError.unsupportedPlayerCount(
                gameType: configuration.gameType,
                count: state.seats.count
            )
        }

        switch configuration {
        case .strokePlay(let config): return StrokePlayEngine.settle(state: state, config: config)
        case .matchPlay(let config): return try MatchPlayEngine.settle(state: state, config: config)
        case .bestBall(let config): return try BestBallEngine.settle(state: state, config: config)
        case .skins(let config):
            return SkinsEngine.settle(state: state, config: config)
        case .nassau(let config):
            return try NassauEngine.settle(state: state, config: config)
        case .stableford(let config):
            return StablefordEngine.settle(state: state, config: config)
        case .nines(let config):
            return try NinesEngine.settle(state: state, config: config)
        case .wolf(let config):
            return WolfEngine.settle(state: state, config: config)
        case .bingoBangoBongo(let config):
            return BingoBangoBongoEngine.settle(state: state, config: config)
        }
    }

    private static func describe<E: GameDescriptor>(_ engine: E.Type) -> GameMetadata {
        GameMetadata(
            gameType: E.gameType,
            displayName: E.displayName,
            summary: E.summary,
            rules: E.rules,
            iconName: E.iconName,
            requiredInputs: E.requiredInputs,
            playerRange: E.playerRange
        )
    }
}
