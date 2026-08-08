import Testing
import Foundation
@testable import RoundPlayEngine

private let alice = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
private let bob = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

private func seats() -> [Seat] {
    [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 0)
    ]
}

private func log(_ holes: [Int: [UUID: Int]]) -> [ScoreEvent] {
    var events: [ScoreEvent] = []
    var seq = 0
    for hole in holes.keys.sorted() {
        for (player, strokes) in holes[hole]!.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            seq += 1
            events.append(ScoreEvent(id: UUID(), hole: hole, playerID: player,
                                     payload: .strokes(strokes), enteredBy: alice, sequence: seq))
        }
    }
    return events
}

@Test("Standard point table maps net score to points")
func standardPointTable() {
    let table = StablefordConfig.standard.pointsTable
    #expect(table.points(netRelativeToPar: 2) == 0)    // double bogey
    #expect(table.points(netRelativeToPar: 3) == 0)    // worse still
    #expect(table.points(netRelativeToPar: 1) == 1)    // bogey
    #expect(table.points(netRelativeToPar: 0) == 2)    // par
    #expect(table.points(netRelativeToPar: -1) == 3)   // birdie
    #expect(table.points(netRelativeToPar: -2) == 4)   // eagle
    #expect(table.points(netRelativeToPar: -3) == 5)   // albatross
}

@Test("Points accumulate across holes and settle on the difference")
func pointsAccumulateAndSettle() {
    // Hole 1 par 4: Alice 3 (birdie, 3pts), Bob 4 (par, 2pts)
    // Hole 2 par 5: Alice 5 (par, 2pts), Bob 7 (double, 0pts)
    let state = RoundState(
        log: log([1: [alice: 3, bob: 4], 2: [alice: 5, bob: 7]]),
        seats: seats(), course: .testPar72
    )
    let result = StablefordEngine.settle(
        state: state,
        config: StablefordConfig(unitStake: 2, pointsTable: .standard)
    )

    #expect(result.points(for: alice) == 5)
    #expect(result.points(for: bob) == 2)
    // Difference of 3 points at $2 = $6 from Bob to Alice.
    #expect(result.money(for: alice) == 6)
    #expect(result.money(for: bob) == -6)
    #expect(result.isZeroSum)
}

@Test("Handicap strokes raise a bogey to a par for points")
func handicapAffectsPoints() {
    let seats = [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 18)
    ]
    // Hole 1 par 4: Bob shoots 5 gross, nets 4 with his shot — a par, worth 2 points.
    let state = RoundState(log: log([1: [alice: 4, bob: 5]]), seats: seats, course: .testPar72)
    let result = StablefordEngine.settle(
        state: state, config: StablefordConfig(unitStake: 1, pointsTable: .standard)
    )

    #expect(result.points(for: bob) == 2)
    #expect(result.points(for: alice) == 2)
    #expect(result.money(for: alice) == 0)
    #expect(result.isZeroSum)
}

@Test("Modified Stableford penalises blowups instead of flooring at zero")
func modifiedTablePenalises() {
    let table = StablefordConfig.modified.pointsTable
    #expect(table.points(netRelativeToPar: 1) == -1)
    #expect(table.points(netRelativeToPar: 2) == -3)
    #expect(table.points(netRelativeToPar: 0) == 0)
    #expect(table.points(netRelativeToPar: -1) == 2)
}
