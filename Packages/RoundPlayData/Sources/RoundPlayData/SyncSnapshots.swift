import Foundation
import RoundPlayEngine

public enum SyncChannel: String, Codable, Sendable {
    case roster
    case courses
    case rounds
}

public struct PlayerSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var handicapIndex: Double?
    public var linkedAccountID: UUID?
    public var lastPlayedAt: Date?
    public var playCount: Int
    public var createdAt: Date

    public init(record: PlayerRecord) {
        id = record.id
        name = record.name
        handicapIndex = record.handicapIndex
        linkedAccountID = record.linkedAccountID
        lastPlayedAt = record.lastPlayedAt
        playCount = record.playCount
        createdAt = record.createdAt
    }

    public func apply(to record: PlayerRecord) {
        record.name = name
        record.handicapIndex = handicapIndex
        record.linkedAccountID = linkedAccountID
        record.lastPlayedAt = lastPlayedAt
        record.playCount = playCount
        record.createdAt = createdAt
    }
}

public struct CourseSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var pars: [Int]
    public var strokeIndexes: [Int]
    public var createdAt: Date
    public var lastPlayedAt: Date?
    public var openGolfID: String?

    public init(record: CourseRecord) {
        id = record.id
        name = record.name
        pars = record.pars
        strokeIndexes = record.strokeIndexes
        createdAt = record.createdAt
        lastPlayedAt = record.lastPlayedAt
        openGolfID = record.openGolfID
    }

    public func apply(to record: CourseRecord) {
        record.name = name
        record.pars = pars
        record.strokeIndexes = strokeIndexes
        record.createdAt = createdAt
        record.lastPlayedAt = lastPlayedAt
        record.openGolfID = openGolfID
    }
}

public struct FavoriteSnapshot: Codable, Sendable, Equatable {
    public var openGolfID: String
    public var name: String
    public var city: String?
    public var state: String?
    public var favoritedAt: Date

    public init(record: FavoriteCourseRecord) {
        openGolfID = record.openGolfID
        name = record.name
        city = record.city
        state = record.state
        favoritedAt = record.favoritedAt
    }
}

public struct SeatSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var playerID: UUID
    public var name: String
    public var courseHandicap: Int
    public var strokeOverride: Int?
    public var position: Int

    public init(record: SeatRecord) {
        id = record.id
        playerID = record.playerID
        name = record.name
        courseHandicap = record.courseHandicap
        strokeOverride = record.strokeOverride
        position = record.position
    }
}

public struct GameSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var gameTypeRaw: String
    public var configurationData: Data

    public init(record: GameInstanceRecord) {
        id = record.id
        gameTypeRaw = record.gameTypeRaw
        configurationData = record.configurationData
    }
}

public struct EventSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var hole: Int
    public var playerID: UUID
    public var payloadData: Data
    public var enteredBy: UUID
    public var enteredByName: String
    public var sequence: Int
    public var recordedAt: Date
    public var deviceID: UUID

    public init(record: ScoreEventRecord) {
        id = record.id
        hole = record.hole
        playerID = record.playerID
        payloadData = record.payloadData
        enteredBy = record.enteredBy
        enteredByName = record.enteredByName
        sequence = record.sequence
        recordedAt = record.recordedAt
        deviceID = record.deviceID
    }
}

public struct RoundSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var courseID: UUID
    public var courseName: String
    public var startedAt: Date
    public var completedAt: Date?
    public var deletedAt: Date?
    public var nextSequence: Int
    public var holesPlayedRaw: String
    public var strokeModeRaw: String
    public var handicapAllowancePercent: Int
    public var maxHandicapStrokes: Int?
    public var seats: [SeatSnapshot]
    public var games: [GameSnapshot]
    public var events: [EventSnapshot]

    public init(record: RoundRecord) {
        id = record.id
        courseID = record.courseID
        courseName = record.courseName
        startedAt = record.startedAt
        completedAt = record.completedAt
        deletedAt = record.deletedAt
        nextSequence = record.nextSequence
        holesPlayedRaw = record.holesPlayedRaw
        strokeModeRaw = record.strokeModeRaw
        handicapAllowancePercent = record.handicapAllowancePercent
        maxHandicapStrokes = record.maxHandicapStrokes
        seats = (record.seats ?? []).map(SeatSnapshot.init)
        games = (record.games ?? []).map(GameSnapshot.init)
        events = (record.events ?? []).map(EventSnapshot.init)
    }
}

public struct RosterPayload: Codable, Sendable {
    public var players: [PlayerSnapshot]
    public init(players: [PlayerSnapshot]) { self.players = players }
}

public struct CoursesPayload: Codable, Sendable {
    public var courses: [CourseSnapshot]
    public var favorites: [FavoriteSnapshot]
    public init(courses: [CourseSnapshot], favorites: [FavoriteSnapshot]) {
        self.courses = courses
        self.favorites = favorites
    }
}

public struct RoundsPayload: Codable, Sendable {
    public var rounds: [RoundSnapshot]
    public init(rounds: [RoundSnapshot]) { self.rounds = rounds }
}

enum SyncCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
