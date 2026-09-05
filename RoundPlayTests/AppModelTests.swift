import Testing
import Foundation
import SwiftData
import RoundPlayEngine
import RoundPlayData
@testable import RoundPlay

private let testCourseID = UUID(uuidString: "84000000-0000-0000-0000-000000000001")!

private func validCourseRecord() -> CourseRecord {
    CourseRecord(
        id: testCourseID,
        name: "Test Links",
        pars: Array(repeating: 4, count: 18),
        strokeIndexes: Array(1...18)
    )
}

private func inMemoryContext() throws -> ModelContext {
    ModelContext(RoundPlaySchema.makeContainer(inMemory: true))
}

@Test("Appearance preferences expose stable labels and schemes")
func appearancePreferenceValues() {
    #expect(AppearancePreference.system.id == "system")
    #expect(AppearancePreference.light.label == "Light")
    #expect(AppearancePreference.dark.colorScheme == .dark)
    #expect(AppearancePreference.system.colorScheme == nil)
}

@Test("Player handicap rounds to whole course strokes")
func playerHandicapRounding() {
    #expect(PlayerRecord(name: "A", handicapIndex: 7.49).courseHandicap == 7)
    #expect(PlayerRecord(name: "B", handicapIndex: 7.5).courseHandicap == 8)
    #expect(PlayerRecord(name: "C").courseHandicap == 0)
}

@Test("Course records reject malformed arrays and convert valid records")
func courseRecordConversion() {
    let valid = validCourseRecord()
    #expect(valid.engineCourse?.totalPar == 72)
    #expect(valid.totalPar == 72)
    #expect(CourseRecord(name: "Incomplete", pars: [4], strokeIndexes: [1]).engineCourse == nil)
}

@Test("Round records preserve hole segment, ordering, and completion flags")
func roundRecordBehavior() {
    let round = RoundRecord(courseID: testCourseID, courseName: "Test Links", holeSegment: .back)
    let first = SeatRecord(playerID: UUID(), name: "Second", courseHandicap: 0, position: 2)
    let second = SeatRecord(playerID: UUID(), name: "First", courseHandicap: 0, position: 1)
    round.seats = [first, second]
    #expect(round.holeSegment == .back)
    #expect(round.orderedSeats.map(\.name) == ["First", "Second"])
    #expect(round.holeSegment.holeRange == 10...18)
    #expect(!round.isComplete)
    round.completedAt = Date()
    #expect(round.isComplete)
    round.deletedAt = Date()
    #expect(round.isDeleted)
}

@Test("Game and score records preserve engine values through JSON storage")
func persistedEngineValues() throws {
    let context = try inMemoryContext()
    let game = try GameInstanceRecord(configuration: .nassau(NassauConfig(unitStake: 5, pressAt: nil)))
    #expect(game.gameType == .nassau)
    #expect(game.configuration == .nassau(NassauConfig(unitStake: 5, pressAt: nil)))

    let event = try ScoreEventRecord(hole: 3, playerID: testCourseID, payload: .wolfDeclaration(.lone), enteredBy: testCourseID, enteredByName: "Keeper", sequence: 4)
    #expect(event.payload == .wolfDeclaration(.lone))
    #expect(event.engineEvent?.hole == 3)
    #expect(event.engineEvent?.enteredBy == testCourseID)
    context.insert(game)
    context.insert(event)
    try context.save()
}

@Test("New round drafts enforce player limits and eligibility")
func newRoundDraftRules() {
    let model = NewRoundModel()
    #expect(model.playerCount == 4)
    model.playerCount = 1
    #expect(model.playerCount == 1)
    model.playerCount = 0
    #expect(model.playerCount == 1)
    model.playerCount = 99
    #expect(model.playerCount == 8)
    model.playerCount = 3
    #expect(model.eligibleGames.contains { $0.gameType == .nines })
    #expect(!model.eligibleGames.contains { $0.gameType == .nassau })
    #expect(!model.canStart)
}

@Test("A round is solo when it has exactly one seat")
func roundIsSoloWithOneSeat() {
    let round = RoundRecord(courseID: testCourseID, courseName: "Test Links")
    #expect(!round.isSolo)

    round.seats = [SeatRecord(playerID: UUID(), name: "Me", courseHandicap: 12, position: 0)]
    #expect(round.isSolo)

    round.seats?.append(SeatRecord(playerID: UUID(), name: "Ann", courseHandicap: 8, position: 1))
    #expect(!round.isSolo)
}

@Test("Player count accepts one player and still refuses zero and nine")
func playerCountAllowsSolo() {
    let model = NewRoundModel()
    #expect(model.seats.count == 4)

    model.playerCount = 1
    #expect(model.seats.count == 1)

    model.playerCount = 0
    #expect(model.seats.count == 1)

    model.playerCount = 9
    #expect(model.seats.count == 8)
}

@Test("A group round keeps its chosen handicap settings")
func groupKeepsChosenHandicap() {
    let model = NewRoundModel()
    #expect(!model.isSolo)
    #expect(model.effectiveHandicapSettings.mode == .offTheLow)
}

/// Every test here reads or writes `MyPlayer.defaultsKey` in the real, process-wide
/// `UserDefaults.standard` — directly, or indirectly through `NewRoundModel.makeSolo`. Swift
/// Testing runs free `@Test` functions concurrently by default, and two of these racing on the
/// same key produced exactly the flake this suite prevents: one test's `resolve` returning the
/// "me" player another test had just created and overwritten the key with. `.serialized` runs
/// this suite's tests one at a time; every other test in the file keeps running in parallel.
@Suite(.serialized)
struct SoloMyPlayerTests {
    @Test("Solo rounds play the full handicap, never off-the-low")
    func soloUsesFullHandicap() throws {
        UserDefaults.standard.removeObject(forKey: MyPlayer.defaultsKey)
        let context = try inMemoryContext()
        let course = validCourseRecord()
        context.insert(course)

        let model = NewRoundModel()
        model.course = course
        model.makeSolo(in: context)

        #expect(model.isSolo)
        #expect(model.effectiveHandicapSettings.mode == .full)
        #expect(model.effectiveHandicapSettings.allowancePercent == 100)
        #expect(model.effectiveHandicapSettings.maxStrokes == nil)

        let round = try #require(model.makeRound(in: context))
        #expect(round.handicapSettings.mode == .full)
        UserDefaults.standard.removeObject(forKey: MyPlayer.defaultsKey)
    }

    @Test("A solo builder shows only course, players and holes")
    func soloSkipsGroupOnlySteps() throws {
        UserDefaults.standard.removeObject(forKey: MyPlayer.defaultsKey)
        let context = try inMemoryContext()
        let solo = NewRoundModel()
        solo.makeSolo(in: context)
        #expect(solo.activeStepsForTesting == [.course, .playerCount, .holes])
        #expect(solo.totalSteps == 3)

        let group = NewRoundModel()
        #expect(group.activeStepsForTesting == [.course, .playerCount, .knownPlayers, .fillRemaining, .strokes, .holes, .games])
        UserDefaults.standard.removeObject(forKey: MyPlayer.defaultsKey)
    }

    @Test("The solo seat is the onboarding player, and is created if it has gone missing")
    func soloSeatResolvesToMe() throws {
        let context = try inMemoryContext()
        UserDefaults.standard.removeObject(forKey: MyPlayer.defaultsKey)

        // Nothing stored: a "Me" player is created and the key written.
        let created = MyPlayer.resolve(in: context)
        #expect(created.name == "Me")
        #expect(UserDefaults.standard.string(forKey: MyPlayer.defaultsKey) == created.id.uuidString)

        // Stored and present: the same record comes back, not a second one.
        #expect(MyPlayer.resolve(in: context).id == created.id)

        // Stored but deleted from the roster: a fresh record replaces it.
        context.delete(created)
        try context.save()
        let replacement = MyPlayer.resolve(in: context)
        #expect(replacement.id != created.id)

        UserDefaults.standard.removeObject(forKey: MyPlayer.defaultsKey)
    }

    @Test("Solo rounds give strokes, so net differs from gross")
    func soloNetDiffersFromGross() throws {
        let context = try inMemoryContext()
        let course = validCourseRecord()
        context.insert(course)

        let me = PlayerRecord(name: "Nik", handicapIndex: 9)
        context.insert(me)
        UserDefaults.standard.set(me.id.uuidString, forKey: MyPlayer.defaultsKey)

        let model = NewRoundModel()
        model.course = course
        model.makeSolo(in: context)
        let round = try #require(model.makeRound(in: context))
        let seat = try #require(round.orderedSeats.first)
        #expect(seat.courseHandicap == 9)

        try EngineBridge.appendStrokes(
            5, hole: 1, playerID: seat.playerID, to: round,
            enteredBy: seat.playerID, enteredByName: seat.name, in: context
        )

        let engineCourse = try #require(course.engineCourse)
        let state = EngineBridge.roundState(for: round, course: engineCourse)
        #expect(state.gross(hole: 1, player: seat.playerID) == 5)
        // Stroke index 1 is hole 1 in the fixture, and a 9-handicap gets a shot there.
        #expect(state.strokesReceived(hole: 1, player: seat.playerID) == 1)
        #expect(state.net(hole: 1, player: seat.playerID) == 4)

        UserDefaults.standard.removeObject(forKey: MyPlayer.defaultsKey)
    }
}

@Test("Guest nickname selection avoids every available collision")
func guestNicknameAvoidance() {
    let used = Set(["Birdie Malone", "Bogey Sanchez"])
    for _ in 0..<30 {
        #expect(!used.contains(GuestNickname.random(avoiding: used)))
    }
}
