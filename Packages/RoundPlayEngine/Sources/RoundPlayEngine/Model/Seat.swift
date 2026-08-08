import Foundation

/// A player's place in a round.
///
/// `courseHandicap` is frozen at round-creation time rather than read live from the player record,
/// so a settled round always recomputes to the same money even after the player's handicap changes.
public struct Seat: Equatable, Sendable, Codable, Identifiable {
    public let playerID: UUID
    public let name: String
    public let courseHandicap: Int

    public var id: UUID { playerID }

    public init(playerID: UUID, name: String, courseHandicap: Int) {
        self.playerID = playerID
        self.name = name
        self.courseHandicap = courseHandicap
    }
}
