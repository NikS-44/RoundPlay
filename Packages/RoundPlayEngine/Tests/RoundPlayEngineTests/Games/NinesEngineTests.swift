import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
private let b = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
private let c = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

private func threesome() -> [Seat] {
    [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 0),
        Seat(playerID: c, name: "Cal", courseHandicap: 0)
    ]
}

private func log(_ holes: [Int: [UUID: Int]]) -> [ScoreEvent] {
    var events: [ScoreEvent] = []
    var seq = 0
    for hole in holes.keys.sorted() {
        for (player, strokes) in holes[hole]!.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            seq += 1
            events.append(ScoreEvent(id: UUID(), hole: hole, playerID: player,
                                     payload: .strokes(strokes), enteredBy: a, sequence: seq))
        }
    }
    return events
}

private func settle(_ holes: [Int: [UUID: Int]], stake: Decimal = 1) throws -> Settlement {
    let state = RoundState(log: log(holes), seats: threesome(), course: .testPar72)
    return try NinesEngine.settle(state: state, config: NinesConfig(unitStake: stake))
}

@Test("Clean finish splits 5-3-1")
func cleanFinish() throws {
    let result = try settle([1: [a: 3, b: 4, c: 5]])
    #expect(result.points(for: a) == 5)
    #expect(result.points(for: b) == 3)
    #expect(result.points(for: c) == 1)
    #expect(result.isZeroSum)
}

@Test("All three tied splits 3-3-3")
func allTied() throws {
    let result = try settle([1: [a: 4, b: 4, c: 4]])
    #expect(result.points(for: a) == 3)
    #expect(result.points(for: b) == 3)
    #expect(result.points(for: c) == 3)
    #expect(result.money(for: a) == 0)
}

@Test("Two tied for low splits 4-4-1")
func twoTiedForLow() throws {
    let result = try settle([1: [a: 3, b: 3, c: 5]])
    #expect(result.points(for: a) == 4)
    #expect(result.points(for: b) == 4)
    #expect(result.points(for: c) == 1)
}

@Test("Two tied for high splits 5-2-2")
func twoTiedForHigh() throws {
    let result = try settle([1: [a: 3, b: 5, c: 5]])
    #expect(result.points(for: a) == 5)
    #expect(result.points(for: b) == 2)
    #expect(result.points(for: c) == 2)
}

@Test("Every hole distributes exactly nine points")
func alwaysNinePoints() throws {
    let scenarios: [[UUID: Int]] = [
        [a: 3, b: 4, c: 5], [a: 4, b: 4, c: 4],
        [a: 3, b: 3, c: 5], [a: 3, b: 5, c: 5]
    ]
    for scenario in scenarios {
        let result = try settle([1: scenario])
        let total = result.standings.reduce(0) { $0 + $1.points }
        #expect(total == 9, "scenario \(scenario) gave \(total)")
    }
}

@Test("Nines rejects anything other than three players")
func requiresThreePlayers() {
    let seats = [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 0)
    ]
    let state = RoundState(log: log([1: [a: 4, b: 4]]), seats: seats, course: .testPar72)
    #expect(throws: NinesEngine.SettleError.requiresThreePlayers) {
        try NinesEngine.settle(state: state, config: NinesConfig(unitStake: 1))
    }
}
