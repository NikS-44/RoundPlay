import Testing
import Foundation
@testable import RoundPlayEngine

private let alice = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
private let bob = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
private let carol = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!

private func scratchSeats() -> [Seat] {
    [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 0),
        Seat(playerID: carol, name: "Carol", courseHandicap: 0)
    ]
}

/// Builds a log from `[hole: [player: grossStrokes]]`.
private func log(_ holes: [Int: [UUID: Int]]) -> [ScoreEvent] {
    var events: [ScoreEvent] = []
    var seq = 0
    for hole in holes.keys.sorted() {
        for (player, strokes) in holes[hole]!.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            seq += 1
            events.append(ScoreEvent(
                id: UUID(), hole: hole, playerID: player,
                payload: .strokes(strokes), enteredBy: alice, sequence: seq
            ))
        }
    }
    return events
}

@Test("Outright low score wins the skin")
func outrightWinTakesSkin() {
    let state = RoundState(
        log: log([1: [alice: 4, bob: 5, carol: 5]]),
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.points(for: alice) == 1)
    // Alice collects the unit from each of the two others.
    #expect(result.money(for: alice) == 10)
    #expect(result.money(for: bob) == -5)
    #expect(result.isZeroSum)
}

@Test("A tie carries the skin to the next hole")
func tieCarriesOver() {
    let state = RoundState(
        log: log([
            1: [alice: 4, bob: 4, carol: 5],   // tied — carries
            2: [alice: 3, bob: 5, carol: 5]    // Alice wins 2 skins
        ]),
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.points(for: alice) == 2)
    #expect(result.money(for: alice) == 20)
    #expect(result.isZeroSum)
}

@Test("Carryover is announced in the hole explanation")
func explanationMentionsCarryover() {
    let state = RoundState(
        log: log([
            1: [alice: 4, bob: 4, carol: 5],
            2: [alice: 3, bob: 5, carol: 5]
        ]),
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))
    let hole2 = result.holeExplanations.first { $0.hole == 2 }

    #expect(hole2?.text.contains("2 skins") == true)
    #expect(hole2?.text.contains("carryover") == true)
}

@Test("Handicap strokes decide the skin on net score")
func netScoreDecidesSkin() {
    let seats = [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 18),
        Seat(playerID: carol, name: "Carol", courseHandicap: 0)
    ]
    // Hole 1: Alice 4 gross (net 4), Bob 5 gross (net 4 with his shot), Carol 6.
    // Alice and Bob tie on net, so the skin carries — gross alone would have given it to Alice.
    let state = RoundState(
        log: log([1: [alice: 4, bob: 5, carol: 6]]),
        seats: seats, course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.points(for: alice) == 0)
    #expect(result.money(for: alice) == 0)
    #expect(result.isZeroSum)
}

@Test("Incomplete holes are skipped rather than treated as zeroes")
func incompleteHolesAreSkipped() {
    let state = RoundState(
        log: log([1: [alice: 4, bob: 5]]),   // Carol has no score
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.standings.allSatisfy { $0.points == 0 })
    #expect(result.isZeroSum)
}

@Test("Unclaimed skins at the end of the round are not paid out")
func unclaimedSkinsExpire() {
    let state = RoundState(
        log: log([1: [alice: 4, bob: 4, carol: 5]]),   // ties, carries, round ends
        seats: scratchSeats(), course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 5))

    #expect(result.standings.allSatisfy { $0.money == 0 })
    #expect(result.isZeroSum)
}
