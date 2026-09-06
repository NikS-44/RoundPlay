#if DEBUG
import Foundation
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// Puts a known round in the watch's own store, for verifying the hole screen and for App Store
/// screenshots.
///
/// The watch normally has no data of its own — everything arrives from the phone over
/// WatchConnectivity. That is fine in the field and useless on a workbench: paired simulators
/// merge rather than replace, so the round you want on screen loses to whatever is already there
/// and there is no way to pick between them from the wrist.
///
/// The phone's `DemoData` is the same idea, and this deliberately seeds the same course and the
/// same four people so a phone and a watch screenshot look like one group's round.
///
/// Wrapped in `#if DEBUG` in its entirety — App Store archives build Release, so none of this is
/// compiled into a shipping binary — and triggered only by an explicit launch argument, so even a
/// debug build never seeds unless asked:
///
///     xcrun simctl launch <device> app.roundplay.RoundPlay.watchkitapp -seedDemoData
///
enum WatchDemoData {
    static let launchArgument = "-seedDemoData"

    static var isRequested: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    @MainActor
    static func seed(into context: ModelContext) {
        wipe(context)

        let course = CourseRecord(
            name: "Pebble Creek",
            pars: [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4],
            strokeIndexes: [1, 11, 17, 3, 7, 15, 13, 5, 9, 2, 16, 12, 4, 8, 18, 14, 6, 10]
        )
        course.lastPlayedAt = Date()
        context.insert(course)

        // Handicaps spread wide enough that the stroke marker actually appears on some holes —
        // Cal off 22 is getting a shot almost everywhere, which is the case worth looking at.
        let people: [(String, Double)] = [("Nik", 9.0), ("Ann", 8.0), ("Ben", 14.0), ("Cal", 22.0)]
        let players = people.map { PlayerRecord(name: $0.0, handicapIndex: $0.1) }
        for player in players {
            player.lastPlayedAt = Date()
            player.playCount = 6
            context.insert(player)
        }

        let round = RoundRecord(courseID: course.id, courseName: course.name)
        round.seats = players.enumerated().map { index, player in
            SeatRecord(playerID: player.id, name: player.name,
                       courseHandicap: player.courseHandicap, position: index)
        }
        context.insert(round)

        // Two holes done and the third part-scored: the hole screen opens mid-entry, with some
        // dots filled and some empty, which is the state the layout has to hold up in.
        let scores: [[Int]] = [[4, 4, 5, 6], [5, 6, 5, 7], [2, 3]]
        let scorekeeper = round.orderedSeats[0]
        for (holeIndex, holeScores) in scores.enumerated() {
            for (seatIndex, strokes) in holeScores.enumerated() {
                try? EngineBridge.appendStrokes(
                    strokes, hole: holeIndex + 1, playerID: round.orderedSeats[seatIndex].playerID,
                    to: round, enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
                    in: context
                )
            }
        }

        try? context.save()
    }

    @MainActor
    private static func wipe(_ context: ModelContext) {
        try? context.delete(model: RoundRecord.self)
        try? context.delete(model: PlayerRecord.self)
        try? context.delete(model: CourseRecord.self)
        try? context.save()
    }
}
#endif
