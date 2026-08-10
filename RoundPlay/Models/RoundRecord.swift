import Foundation
import SwiftData
import RoundPlayEngine

/// A group's round: a course, the seats, and the games being played.
@Model
final class RoundRecord {
    var id: UUID = UUID()
    var courseID: UUID = UUID()
    var courseName: String = ""
    var startedAt: Date = Date()
    var completedAt: Date?
    /// Soft delete — "Delete Round" sets this instead of removing the record, so it can show up
    /// in Recently Deleted and be restored. Only the permanent-delete action in that list actually
    /// removes it from the store.
    var deletedAt: Date?
    /// Monotonic counter for `ScoreEventRecord.sequence`. Phase 2 hands this to the server.
    var nextSequence: Int = 1
    /// Which holes this round plays — `RoundSegment.rawValue`. Stored as a string, same reasoning
    /// as `GameInstanceRecord.gameTypeRaw`: schema stays stable if the engine's cases change.
    var holesPlayedRaw: String = RoundSegment.total.rawValue

    @Relationship(deleteRule: .cascade) var seats: [SeatRecord]? = []
    @Relationship(deleteRule: .cascade) var games: [GameInstanceRecord]? = []
    @Relationship(deleteRule: .cascade) var events: [ScoreEventRecord]? = []

    init(id: UUID = UUID(), courseID: UUID, courseName: String, holeSegment: RoundSegment = .total) {
        self.id = id
        self.courseID = courseID
        self.courseName = courseName
        self.holesPlayedRaw = holeSegment.rawValue
    }

    var orderedSeats: [SeatRecord] {
        (seats ?? []).sorted { $0.position < $1.position }
    }

    var isComplete: Bool { completedAt != nil }
    var isDeleted: Bool { deletedAt != nil }

    var holeSegment: RoundSegment {
        RoundSegment(rawValue: holesPlayedRaw) ?? .total
    }
}

extension RoundSegment {
    /// The physical holes this segment covers — distinct from `contains(hole:)`, which answers
    /// "is this hole in the segment" rather than "what's the first/last hole to navigate to."
    var holeRange: ClosedRange<Int> {
        switch self {
        case .front: 1...9
        case .back: 10...18
        case .total: 1...18
        }
    }
}

/// A player's place in a round.
///
/// `name` and `courseHandicap` are **copied** from `PlayerRecord` rather than referenced, so a
/// finished round always recomputes to the same money even after the player's handicap changes.
@Model
final class SeatRecord {
    var id: UUID = UUID()
    var playerID: UUID = UUID()
    var name: String = ""
    var courseHandicap: Int = 0
    /// Tee order. Drives the Wolf rotation, so it must be stable.
    var position: Int = 0

    init(id: UUID = UUID(), playerID: UUID, name: String, courseHandicap: Int, position: Int) {
        self.id = id
        self.playerID = playerID
        self.name = name
        self.courseHandicap = courseHandicap
        self.position = position
    }

    var engineSeat: Seat {
        Seat(playerID: playerID, name: name, courseHandicap: courseHandicap)
    }
}

/// One game running in a round. A round commonly runs two — Skins plus a Nassau.
@Model
final class GameInstanceRecord {
    var id: UUID = UUID()
    var gameTypeRaw: String = ""
    /// `GameConfiguration` encoded as JSON. Stored opaquely so adding a game or a config field
    /// never touches the schema.
    var configurationData: Data = Data()

    init(id: UUID = UUID(), configuration: GameConfiguration) throws {
        self.id = id
        self.gameTypeRaw = configuration.gameType.rawValue
        self.configurationData = try JSONEncoder().encode(configuration)
    }

    var gameType: GameType? { GameType(rawValue: gameTypeRaw) }

    var configuration: GameConfiguration? {
        try? JSONDecoder().decode(GameConfiguration.self, from: configurationData)
    }
}
