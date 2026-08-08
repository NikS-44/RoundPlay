import Foundation

/// A game plus the settings the group agreed on.
public enum GameConfiguration: Equatable, Sendable, Codable {
    case skins(SkinsConfig)
    case nassau(NassauConfig)
    case stableford(StablefordConfig)
    case nines(NinesConfig)
    case wolf(WolfConfig)
    case bingoBangoBongo(BingoBangoBongoConfig)

    public var gameType: GameType {
        switch self {
        case .skins: .skins
        case .nassau: .nassau
        case .stableford: .stableford
        case .nines: .nines
        case .wolf: .wolf
        case .bingoBangoBongo: .bingoBangoBongo
        }
    }
}

/// Static facts about a game, for the library screen and the scorecard's input rendering.
public struct GameMetadata: Equatable, Sendable, Identifiable {
    public let gameType: GameType
    public let displayName: String
    public let summary: String
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
            requiredInputs: E.requiredInputs,
            playerRange: E.playerRange
        )
    }
}
