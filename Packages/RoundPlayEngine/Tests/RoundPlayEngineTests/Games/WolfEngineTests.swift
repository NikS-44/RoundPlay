import Testing
import Foundation
@testable import RoundPlayEngine

private let p1 = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
private let p2 = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
private let p3 = UUID(uuidString: "60000000-0000-0000-0000-000000000003")!
private let p4 = UUID(uuidString: "60000000-0000-0000-0000-000000000004")!

private func foursome() -> [Seat] {
    [
        Seat(playerID: p1, name: "One", courseHandicap: 0),
        Seat(playerID: p2, name: "Two", courseHandicap: 0),
        Seat(playerID: p3, name: "Three", courseHandicap: 0),
        Seat(playerID: p4, name: "Four", courseHandicap: 0)
    ]
}

private func makeLog(
    hole: Int,
    declaration: WolfDeclaration,
    wolf: UUID,
    scores: [UUID: Int]
) -> [ScoreEvent] {
    var events = [
        ScoreEvent(id: UUID(), hole: hole, playerID: wolf,
                   payload: .wolfDeclaration(declaration), enteredBy: wolf, sequence: 1)
    ]
    var seq = 1
    for (player, strokes) in scores.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
        seq += 1
        events.append(ScoreEvent(id: UUID(), hole: hole, playerID: player,
                                 payload: .strokes(strokes), enteredBy: wolf, sequence: seq))
    }
    return events
}

@Test("The Wolf rotates through the seats in order")
func wolfRotates() {
    let seats = foursome()
    #expect(WolfEngine.wolf(forHole: 1, seats: seats).playerID == p1)
    #expect(WolfEngine.wolf(forHole: 2, seats: seats).playerID == p2)
    #expect(WolfEngine.wolf(forHole: 4, seats: seats).playerID == p4)
    #expect(WolfEngine.wolf(forHole: 5, seats: seats).playerID == p1)
    #expect(WolfEngine.wolf(forHole: 17, seats: seats).playerID == p1)
}

@Test("Wolf and partner beating the field scores a point each")
func partnershipWins() {
    let log = makeLog(
        hole: 1, declaration: .partner(p2), wolf: p1,
        scores: [p1: 4, p2: 4, p3: 5, p4: 5]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p1) == 1)
    #expect(result.points(for: p2) == 1)
    #expect(result.points(for: p3) == 0)
    #expect(result.points(for: p4) == 0)
    #expect(result.isZeroSum)
}

@Test("The field beating the Wolf pair scores a point each to the field")
func fieldWins() {
    let log = makeLog(
        hole: 1, declaration: .partner(p2), wolf: p1,
        scores: [p1: 5, p2: 5, p3: 4, p4: 6]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p3) == 1)
    #expect(result.points(for: p4) == 1)
    #expect(result.points(for: p1) == 0)
    #expect(result.isZeroSum)
}

@Test("A winning Lone Wolf takes four points")
func loneWolfWins() {
    let log = makeLog(
        hole: 1, declaration: .lone, wolf: p1,
        scores: [p1: 3, p2: 4, p3: 4, p4: 4]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p1) == 4)
    #expect(result.points(for: p2) == 0)
    #expect(result.isZeroSum)
}

@Test("A losing Lone Wolf pays a point to every opponent")
func loneWolfLoses() {
    let log = makeLog(
        hole: 1, declaration: .lone, wolf: p1,
        scores: [p1: 6, p2: 4, p3: 5, p4: 5]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p1) == 0)
    #expect(result.points(for: p2) == 1)
    #expect(result.points(for: p3) == 1)
    #expect(result.points(for: p4) == 1)
    #expect(result.isZeroSum)
}

@Test("A tied hole scores nothing for anyone")
func tiedHoleScoresNothing() {
    let log = makeLog(
        hole: 1, declaration: .partner(p2), wolf: p1,
        scores: [p1: 4, p2: 5, p3: 4, p4: 5]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.standings.allSatisfy { $0.points == 0 })
}

@Test("Holes with no declaration are skipped")
func undeclaredHolesSkipped() {
    var log: [ScoreEvent] = []
    var seq = 0
    for (player, strokes) in [(p1, 4), (p2, 5), (p3, 5), (p4, 5)] {
        seq += 1
        log.append(ScoreEvent(id: UUID(), hole: 1, playerID: player,
                              payload: .strokes(strokes), enteredBy: p1, sequence: seq))
    }
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.standings.allSatisfy { $0.points == 0 })
}

@Test("Better-ball uses the lower net of the pair, not the sum")
func betterBallUsesLowerNet() {
    // Wolf pair: 3 and 7 (better ball 3). Field: 4 and 4 (better ball 4). Wolf pair wins.
    let log = makeLog(
        hole: 1, declaration: .partner(p2), wolf: p1,
        scores: [p1: 3, p2: 7, p3: 4, p4: 4]
    )
    let state = RoundState(log: log, seats: foursome(), course: .testPar72)
    let result = WolfEngine.settle(state: state, config: .standard(unitStake: 1))

    #expect(result.points(for: p1) == 1)
    #expect(result.points(for: p2) == 1)
}
