import Foundation

/// The launch games supported by the scoring library.
public enum GameType: String, Equatable, Sendable, Codable, CaseIterable {
    case strokePlay
    case matchPlay
    case bestBall
    case skins
    case nassau
    case stableford
    case nines
    case wolf
    case bingoBangoBongo
    case sixes
}

/// What a game needs the scorecard UI to collect beyond gross strokes.
///
/// The hole screen renders prompts from this set. It does not know what Wolf *is* — it knows
/// that a game declaring `.partnerChoice` needs a partner picker before scores are entered.
public enum InputKind: String, Equatable, Sendable, Codable, CaseIterable {
    case strokes
    case partnerChoice
    case holeEvents
}

/// Static facts about a game, used to build the library screen and drive the scorecard UI.
public protocol GameDescriptor {
    static var gameType: GameType { get }
    static var displayName: String { get }
    /// One line, plain English, written for someone who has never played it.
    static var summary: String { get }
    /// The full rules, in plain English — a few short paragraphs, no jargon left unexplained.
    /// Shown on the game's detail screen; `\n\n` separates paragraphs.
    static var rules: String { get }
    /// SF Symbol name for the library card and game-selection row.
    static var iconName: String { get }
    static var requiredInputs: Set<InputKind> { get }
    static var playerRange: ClosedRange<Int> { get }
}
