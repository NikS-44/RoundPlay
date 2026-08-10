import Foundation

/// A player's place in a round.
///
/// `courseHandicap` is frozen at round-creation time rather than read live from the player record,
/// so a settled round always recomputes to the same money even after the player's handicap changes.
public struct Seat: Equatable, Sendable, Codable, Identifiable {
    public let playerID: UUID
    public let name: String
    public let courseHandicap: Int
    /// Strokes this seat was given by hand, replacing anything derived from `courseHandicap`.
    ///
    /// Most groups don't compute a handicap at all — they agree a number out loud ("you give me
    /// four"). That number is the final answer, so it bypasses the allowance, the cap and the
    /// off-the-low subtraction rather than feeding through them. `nil` means "derive it".
    public let strokeOverride: Int?

    public var id: UUID { playerID }

    public init(playerID: UUID, name: String, courseHandicap: Int, strokeOverride: Int? = nil) {
        self.playerID = playerID
        self.name = name
        self.courseHandicap = courseHandicap
        self.strokeOverride = strokeOverride
    }
}
