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
    /// Monotonic counter for `ScoreEventRecord.sequence`. Phase 2 hands this to the server.
    var nextSequence: Int = 1

    @Relationship(deleteRule: .cascade) var seats: [SeatRecord]? = []
    @Relationship(deleteRule: .cascade) var games: [GameInstanceRecord]? = []
    @Relationship(deleteRule: .cascade) var events: [ScoreEventRecord]? = []

    init(id: UUID = UUID(), courseID: UUID, courseName: String) {
        self.id = id
        self.courseID = courseID
        self.courseName = courseName
    }

    var orderedSeats: [SeatRecord] {
        (seats ?? []).sorted { $0.position < $1.position }
    }

    var isComplete: Bool { completedAt != nil }
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
