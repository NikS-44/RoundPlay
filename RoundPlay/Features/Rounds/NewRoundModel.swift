import Foundation
import Observation
import SwiftData
import RoundPlayEngine

/// Builds a round across the three setup steps.
@Observable
final class NewRoundModel {
    var course: CourseRecord?
    var selectedPlayers: [PlayerRecord] = []
    var configurations: [GameConfiguration] = []

    /// Games whose supported player count matches the current group.
    ///
    /// Filtering rather than showing-then-erroring is deliberate: a threesome should never be
    /// offered Wolf-for-four and then told no.
    var eligibleGames: [GameMetadata] {
        GameLibrary.all.filter { $0.playerRange.contains(selectedPlayers.count) }
    }

    var canStart: Bool {
        course?.engineCourse != nil && selectedPlayers.count >= 2 && !configurations.isEmpty
    }

    func makeRound(in context: ModelContext) -> RoundRecord? {
        guard let course, course.engineCourse != nil else { return nil }

        let round = RoundRecord(courseID: course.id, courseName: course.name)
        round.seats = selectedPlayers.enumerated().map { index, player in
            SeatRecord(
                playerID: player.id,
                name: player.name,
                courseHandicap: player.courseHandicap,
                position: index
            )
        }
        round.games = configurations.compactMap { try? GameInstanceRecord(configuration: $0) }

        context.insert(round)
        course.lastPlayedAt = Date()
        for player in selectedPlayers {
            player.lastPlayedAt = Date()
            player.playCount += 1
        }
        try? context.save()
        return round
    }
}
