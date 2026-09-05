#if DEBUG
import Foundation
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// Fills a real store with the round used for App Store screenshots.
///
/// `PreviewData` builds the same round for SwiftUI previews, but into an in-memory container that
/// only exists inside a preview process — screenshots need it in the app's actual store, on a
/// simulator, reachable by tapping through the app.
///
/// Wrapped in `#if DEBUG` in its entirety: App Store archives build Release, so none of this is
/// compiled into a shipping binary. Triggered explicitly with a launch argument, so even a debug
/// build never seeds unless asked.
///
///     xcrun simctl launch <device> app.roundplay.RoundPlay -seedDemoData
///
/// Seeding wipes what is already there, so repeated runs give byte-identical screenshots instead
/// of piling a second round on top of the first.
enum DemoData {
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

        // The first player is "me": the solo round and the onboarding seat both resolve through
        // MyPlayer, so the screenshots read as one person's phone rather than a stranger's.
        let people: [(String, Double)] = [("Nik", 9.0), ("Ann", 8.0), ("Ben", 14.0), ("Cal", 22.0)]
        let players = people.map { PlayerRecord(name: $0.0, handicapIndex: $0.1) }
        for player in players {
            player.lastPlayedAt = Date()
            player.playCount = 6
            context.insert(player)
        }
        UserDefaults.standard.set(players[0].id.uuidString, forKey: MyPlayer.defaultsKey)
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        seedGroupRound(course: course, players: players, in: context)
        seedSoloRound(course: course, me: players[0], in: context)

        try? context.save()
    }

    /// A foursome mid-round, scoring only.
    ///
    /// Deliberately no money game configured. The store listing leads with keeping the card, not
    /// with settling bets — dollar figures and a "who owes who" screen are the fastest way to get
    /// a scorekeeping app read as a gambling one. The side games are still the app's differentiator
    /// and still get their own screenshot, via the games library and its rules.
    @MainActor
    private static func seedGroupRound(course: CourseRecord, players: [PlayerRecord], in context: ModelContext) {
        let round = RoundRecord(courseID: course.id, courseName: course.name)
        round.seats = players.enumerated().map { index, player in
            SeatRecord(playerID: player.id, name: player.name,
                       courseHandicap: player.courseHandicap, position: index)
        }
        context.insert(round)

        // Seven holes: enough for standings to have separated and for the scorecard grid to look
        // played-in, while still leaving the round clearly in progress.
        let scores: [[Int]] = [
            [4, 4, 5, 6], [5, 6, 5, 7], [2, 3, 4, 4], [4, 5, 4, 6],
            [4, 4, 6, 5], [3, 3, 4, 5], [5, 6, 5, 6],
        ]
        append(scores, to: round, in: context)
    }

    /// A solo round far enough along that the header carries a running score.
    @MainActor
    private static func seedSoloRound(course: CourseRecord, me: PlayerRecord, in context: ModelContext) {
        let round = RoundRecord(courseID: course.id, courseName: course.name)
        round.seats = [SeatRecord(playerID: me.id, name: me.name,
                                  courseHandicap: me.courseHandicap, position: 0)]
        round.handicapSettings = HandicapSettings(mode: .full, allowancePercent: 100, maxStrokes: nil)
        context.insert(round)

        append([[4], [5], [3], [4], [4], [3]], to: round, in: context)
    }

    @MainActor
    private static func append(_ scores: [[Int]], to round: RoundRecord, in context: ModelContext) {
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
    }

    /// Clears every record type the screenshots touch, so a reseed replaces rather than appends.
    @MainActor
    private static func wipe(_ context: ModelContext) {
        try? context.delete(model: RoundRecord.self)
        try? context.delete(model: PlayerRecord.self)
        try? context.delete(model: CourseRecord.self)
        try? context.delete(model: FavoriteCourseRecord.self)
        try? context.save()
    }
}
#endif
