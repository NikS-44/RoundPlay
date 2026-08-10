import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
private let b = UUID(uuidString: "70000000-0000-0000-0000-000000000002")!

@Test("Library exposes metadata for all launch games")
func libraryListsAllGames() {
    #expect(GameLibrary.all.count == 9)
    #expect(Set(GameLibrary.all.map(\.gameType)) == Set(GameType.allCases))
}

@Test("Metadata reports the inputs the scorecard must collect")
func metadataReportsInputs() {
    #expect(GameLibrary.metadata(for: .wolf).requiredInputs.contains(.partnerChoice))
    #expect(GameLibrary.metadata(for: .bingoBangoBongo).requiredInputs == [.holeEvents])
    #expect(GameLibrary.metadata(for: .skins).requiredInputs == [.strokes])
}

@Test("Every game has a non-empty plain-English summary")
func everyGameHasASummary() {
    for metadata in GameLibrary.all {
        #expect(metadata.summary.isEmpty == false, "\(metadata.gameType) has no summary")
        #expect(metadata.displayName.isEmpty == false)
    }
}

@Test("Dispatcher routes a configuration to the right engine")
func dispatcherRoutes() throws {
    let seats = [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 0)
    ]
    let log = [
        ScoreEvent(id: UUID(), hole: 1, playerID: a, payload: .strokes(4), enteredBy: a, sequence: 1),
        ScoreEvent(id: UUID(), hole: 1, playerID: b, payload: .strokes(5), enteredBy: a, sequence: 2)
    ]
    let state = RoundState(log: log, seats: seats, course: .testPar72)

    let result = try GameLibrary.settle(
        .skins(SkinsConfig(unitStake: 5)), state: state
    )
    #expect(result.gameType == .skins)
    #expect(result.money(for: a) == 5)
}

@Test("Player count is validated against the game's supported range")
func playerCountIsValidated() {
    let seats = (1...6).map { Seat(playerID: UUID(), name: "P\($0)", courseHandicap: 0) }
    let state = RoundState(log: [], seats: seats, course: .testPar72)

    #expect(throws: GameLibrary.LibraryError.unsupportedPlayerCount(gameType: .wolf, count: 6)) {
        try GameLibrary.settle(.wolf(.standard(unitStake: 1)), state: state)
    }
}
