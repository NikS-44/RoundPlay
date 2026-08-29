import Testing
import Foundation
@testable import RoundPlayEngine

private let sa = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
private let sb = UUID(uuidString: "90000000-0000-0000-0000-000000000002")!
private let sc = UUID(uuidString: "90000000-0000-0000-0000-000000000003")!
private let sd = UUID(uuidString: "90000000-0000-0000-0000-000000000004")!

private func foursome() -> [Seat] {
    [
        Seat(playerID: sa, name: "Ann", courseHandicap: 0),
        Seat(playerID: sb, name: "Ben", courseHandicap: 0),
        Seat(playerID: sc, name: "Cal", courseHandicap: 0),
        Seat(playerID: sd, name: "Dee", courseHandicap: 0)
    ]
}

private func log(_ scores: [(Int, UUID, Int)]) -> [ScoreEvent] {
    scores.enumerated().map { i, item in
        ScoreEvent(id: UUID(), hole: item.0, playerID: item.1, payload: .strokes(item.2), enteredBy: sa, sequence: i + 1)
    }
}

@Test("Pairings rotate every six holes and every player partners with every other exactly once")
func pairingsRotate() {
    #expect(SixesEngine.teams(forHole: 1).teamA == [0, 1])
    #expect(SixesEngine.teams(forHole: 6).teamA == [0, 1])
    #expect(SixesEngine.teams(forHole: 7).teamA == [0, 2])
    #expect(SixesEngine.teams(forHole: 12).teamA == [0, 2])
    #expect(SixesEngine.teams(forHole: 13).teamA == [0, 3])
    #expect(SixesEngine.teams(forHole: 18).teamA == [0, 3])
}

@Test("A nine-hole round still advances into the second pairing at hole 7")
func pairingsSurviveShortRounds() {
    #expect(SixesEngine.teams(forHole: 7).teamA == SixesEngine.teams(forHole: 12).teamA)
    #expect(SixesEngine.teams(forHole: 7).teamA != SixesEngine.teams(forHole: 1).teamA)
}

@Test("Best ball within the first six-hole pairing pays the winning pair from the other pair")
func firstSegmentSettles() throws {
    let state = RoundState(log: log([
        (1, sa, 3), (1, sb, 8), (1, sc, 4), (1, sd, 5) // seats 0+1 (Ann+Ben) vs 2+3 (Cal+Dee): Ann's 3 beats Cal's 4
    ]), seats: foursome(), course: .testPar72)
    let result = try SixesEngine.settle(state: state, config: SixesConfig(unitStake: 2))
    #expect(result.points(for: sa) == 1)
    #expect(result.points(for: sb) == 1)
    #expect(result.points(for: sc) == 0)
    #expect(result.money(for: sa) == 2)
    #expect(result.money(for: sc) == -2)
    #expect(result.isZeroSum)
}

@Test("Money accrues to whoever is on the winning pair for that hole's rotation, not a fixed team")
func rotationChangesWhoIsPartnered() throws {
    let state = RoundState(log: log([
        (1, sa, 3), (1, sb, 8), (1, sc, 4), (1, sd, 5), // hole 1: Ann+Ben vs Cal+Dee -> Ann+Ben win
        (7, sa, 3), (7, sc, 8), (7, sb, 4), (7, sd, 5)  // hole 7: Ann+Cal vs Ben+Dee -> Ann+Cal win
    ]), seats: foursome(), course: .testPar72)
    let result = try SixesEngine.settle(state: state, config: SixesConfig(unitStake: 1))
    // Ann partnered a winner both times: +2. Ben won hole 1 but lost hole 7 (now against Ann): net 0.
    #expect(result.money(for: sa) == 2)
    #expect(result.money(for: sb) == 0)
    // Cal lost hole 1 (paired with Dee) but won hole 7 (paired with Ann): net 0.
    #expect(result.money(for: sc) == 0)
    // Dee lost both, each time paired with a different partner: -2.
    #expect(result.money(for: sd) == -2)
    #expect(result.isZeroSum)
}

@Test("A halved hole pays nothing")
func halvedHolePaysNothing() throws {
    let state = RoundState(log: log([
        (1, sa, 4), (1, sb, 4), (1, sc, 4), (1, sd, 4)
    ]), seats: foursome(), course: .testPar72)
    let result = try SixesEngine.settle(state: state, config: SixesConfig(unitStake: 5))
    #expect(result.isZeroSum)
    #expect(result.money(for: sa) == 0)
    #expect(result.money(for: sc) == 0)
}

@Test("Sixes requires exactly four players")
func requiresFourPlayers() {
    let seats = Array(foursome().prefix(3))
    let state = RoundState(log: [], seats: seats, course: .testPar72)
    #expect(throws: SixesEngine.SettleError.requiresFourPlayers) {
        try SixesEngine.settle(state: state, config: SixesConfig(unitStake: 1))
    }
}
