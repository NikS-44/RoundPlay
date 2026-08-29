import Foundation
import SwiftData
import RoundPlayEngine

@Model
public final class RoundRecord {
    public var id: UUID = UUID()
    public var courseID: UUID = UUID()
    public var courseName: String = ""
    public var startedAt: Date = Date()
    public var completedAt: Date?
    public var deletedAt: Date?
    public var nextSequence: Int = 1
    public var holesPlayedRaw: String = RoundSegment.total.rawValue
    public var strokeModeRaw: String = StrokeMode.full.rawValue
    public var handicapAllowancePercent: Int = 100
    public var maxHandicapStrokes: Int?

    @Relationship(deleteRule: .cascade) public var seats: [SeatRecord]? = []
    @Relationship(deleteRule: .cascade) public var games: [GameInstanceRecord]? = []
    @Relationship(deleteRule: .cascade) public var events: [ScoreEventRecord]? = []

    public init(id: UUID = UUID(), courseID: UUID, courseName: String, holeSegment: RoundSegment = .total) {
        self.id = id
        self.courseID = courseID
        self.courseName = courseName
        self.holesPlayedRaw = holeSegment.rawValue
    }

    public var orderedSeats: [SeatRecord] {
        (seats ?? []).sorted { $0.position < $1.position }
    }

    public var isComplete: Bool { completedAt != nil }
    public var isDeleted: Bool { deletedAt != nil }

    public var holeSegment: RoundSegment {
        RoundSegment(rawValue: holesPlayedRaw) ?? .total
    }

    public var handicapSettings: HandicapSettings {
        get {
            HandicapSettings(
                mode: StrokeMode(rawValue: strokeModeRaw) ?? .full,
                allowancePercent: handicapAllowancePercent,
                maxStrokes: maxHandicapStrokes
            )
        }
        set {
            strokeModeRaw = newValue.mode.rawValue
            handicapAllowancePercent = newValue.allowancePercent
            maxHandicapStrokes = newValue.maxStrokes
        }
    }

    public func bestBallTeamLabel(for seat: SeatRecord) -> String? {
        let teamA = (games ?? []).compactMap { game -> Set<Int>? in
            guard case .bestBall(let config) = game.configuration else { return nil }
            return config.teamASeatPositions
        }.first
        guard let teamA, let position = orderedSeats.firstIndex(where: { $0.id == seat.id }) else {
            return nil
        }
        return teamA.contains(position) ? "A" : "B"
    }
}

extension RoundSegment {
    public var holeRange: ClosedRange<Int> {
        switch self {
        case .front: 1...9
        case .back: 10...18
        case .total: 1...18
        }
    }
}

@Model
public final class SeatRecord {
    public var id: UUID = UUID()
    public var playerID: UUID = UUID()
    public var name: String = ""
    public var courseHandicap: Int = 0
    public var strokeOverride: Int?
    public var position: Int = 0

    public init(id: UUID = UUID(), playerID: UUID, name: String, courseHandicap: Int, position: Int) {
        self.id = id
        self.playerID = playerID
        self.name = name
        self.courseHandicap = courseHandicap
        self.position = position
    }

    public var engineSeat: Seat {
        Seat(
            playerID: playerID,
            name: name,
            courseHandicap: courseHandicap,
            strokeOverride: strokeOverride
        )
    }
}

@Model
public final class GameInstanceRecord {
    public var id: UUID = UUID()
    public var gameTypeRaw: String = ""
    public var configurationData: Data = Data()

    public init(id: UUID = UUID(), configuration: GameConfiguration) throws {
        self.id = id
        self.gameTypeRaw = configuration.gameType.rawValue
        self.configurationData = try JSONEncoder().encode(configuration)
    }

    public init(id: UUID, gameTypeRaw: String, configurationData: Data) {
        self.id = id
        self.gameTypeRaw = gameTypeRaw
        self.configurationData = configurationData
    }

    public var gameType: GameType? { GameType(rawValue: gameTypeRaw) }

    public var configuration: GameConfiguration? {
        try? JSONDecoder().decode(GameConfiguration.self, from: configurationData)
    }
}
