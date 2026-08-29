import Foundation
import SwiftData
import RoundPlayEngine

public enum WatchRoundFactory {
    public static func makeRound(
        course: CourseRecord,
        players: [PlayerRecord],
        configurations: [GameConfiguration],
        copyingHandicapsFrom previous: RoundRecord? = nil,
        in context: ModelContext
    ) -> RoundRecord? {
        guard course.engineCourse != nil, !players.isEmpty else { return nil }
        let round = RoundRecord(courseID: course.id, courseName: course.name, holeSegment: previous?.holeSegment ?? .total)
        if let previous {
            round.handicapSettings = previous.handicapSettings
        }
        var seats: [SeatRecord] = []
        for (index, player) in players.enumerated() {
            let copied = previous?.orderedSeats.first { $0.playerID == player.id }
            let seat = SeatRecord(
                playerID: player.id,
                name: player.name,
                courseHandicap: copied?.courseHandicap ?? player.courseHandicap,
                position: index
            )
            seat.strokeOverride = copied?.strokeOverride
            seats.append(seat)
            player.lastPlayedAt = Date()
            player.playCount += 1
        }
        round.seats = seats
        round.games = configurations.compactMap { try? GameInstanceRecord(configuration: $0) }
        context.insert(round)
        course.lastPlayedAt = Date()
        try? context.save()
        EngineBridge.onLocalChange?()
        return round
    }
}
