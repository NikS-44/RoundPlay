import Foundation
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// Realistic sample data for previews.
///
/// Previews are this phase's test surface, so this builds a *partially played* round — the state
/// most screens are actually rendered in — rather than an empty or completed one.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = RoundPlaySchema.makeContainer(inMemory: true)
        let context = container.mainContext

        let course = CourseRecord(
            name: "Pebble Creek",
            pars: [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4],
            strokeIndexes: [1, 11, 17, 3, 7, 15, 13, 5, 9, 2, 16, 12, 4, 8, 18, 14, 6, 10]
        )
        course.lastPlayedAt = Date()
        context.insert(course)

        let players = [
            ("Ann", 8.0), ("Ben", 14.0), ("Cal", 22.0), ("Dee", 3.0)
        ].map { PlayerRecord(name: $0.0, handicapIndex: $0.1) }
        players.forEach {
            $0.lastPlayedAt = Date()
            $0.playCount = 6
            context.insert($0)
        }

        let round = RoundRecord(courseID: course.id, courseName: course.name)
        round.seats = players.enumerated().map { index, player in
            SeatRecord(playerID: player.id, name: player.name,
                       courseHandicap: player.courseHandicap, position: index)
        }
        round.games = [try? GameInstanceRecord(configuration: .skins(SkinsConfig(unitStake: 5)))]
            .compactMap { $0 }
        context.insert(round)

        // Five holes played, so dashboards and standings have something to show.
        let scores: [[Int]] = [
            [4, 5, 6, 4], [5, 6, 7, 5], [3, 4, 4, 3], [4, 4, 6, 4], [5, 5, 5, 4]
        ]
        for (holeIndex, holeScores) in scores.enumerated() {
            for (seatIndex, strokes) in holeScores.enumerated() {
                let seat = round.orderedSeats[seatIndex]
                try? EngineBridge.appendStrokes(
                    strokes, hole: holeIndex + 1, playerID: seat.playerID, to: round,
                    enteredBy: round.orderedSeats[0].playerID,
                    enteredByName: round.orderedSeats[0].name,
                    in: context
                )
            }
        }

        try? context.save()
        return container
    }()

    static var sampleRound: RoundRecord {
        (try? container.mainContext.fetch(FetchDescriptor<RoundRecord>()))?.first
            ?? RoundRecord(courseID: UUID(), courseName: "Preview")
    }
}

extension Course {
    /// Engine course matching `PreviewData`'s Pebble Creek.
    static var previewCourse: Course {
        let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4]
        let strokeIndexes = [1, 11, 17, 3, 7, 15, 13, 5, 9, 2, 16, 12, 4, 8, 18, 14, 6, 10]
        let holes = (0..<18).map {
            Hole(number: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0])
        }
        return Course(id: UUID(), name: "Pebble Creek", holes: holes)
    }
}
