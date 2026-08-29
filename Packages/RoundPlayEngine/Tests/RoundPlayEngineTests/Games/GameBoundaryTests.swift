import Testing
import Foundation
@testable import RoundPlayEngine

private let ga = UUID(uuidString: "83000000-0000-0000-0000-000000000001")!
private let gb = UUID(uuidString: "83000000-0000-0000-0000-000000000002")!

private func twoSeats() -> [Seat] {
    [Seat(playerID: ga, name: "A", courseHandicap: 0), Seat(playerID: gb, name: "B", courseHandicap: 0)]
}

private func strokeLog(_ scores: [(Int, UUID, Int)]) -> [ScoreEvent] {
    scores.enumerated().map { offset, item in
        ScoreEvent(id: UUID(), hole: item.0, playerID: item.1, payload: .strokes(item.2), enteredBy: ga, sequence: offset + 1)
    }
}

@Test("Stableford clamps better-than-table scores to the best defined value")
func stablefordBestBoundary() {
    #expect(StablefordPointsTable.standard.points(netRelativeToPar: -4) == 5)
    #expect(StablefordPointsTable.modified.points(netRelativeToPar: -4) == 8)
    #expect(StablefordPointsTable.standard.points(netRelativeToPar: 99) == 0)
}

@Test("Nassau ignores incomplete holes and settles completed segments independently")
func nassauIncompleteRound() throws {
    var scores: [(Int, UUID, Int)] = []
    for hole in 1...9 {
        scores += [(hole, ga, 4), (hole, gb, hole == 1 ? 5 : 4)]
    }
    scores.append((10, ga, 4)) // back and total remain incomplete
    let state = RoundState(log: strokeLog(scores), seats: twoSeats(), course: .testPar72)
    let result = try NassauEngine.settle(state: state, config: NassauConfig(unitStake: 7, pressAt: nil))
    // The front and total bets are both won; the incomplete back bet is ignored.
    #expect(result.money(for: ga) == 14)
    #expect(result.money(for: gb) == -14)
    #expect(result.holeExplanations.count == 9)
}

@Test("Skins can use a no-carry house rule")
func skinsNoCarryRule() {
    let seats = twoSeats()
    let state = RoundState(
        log: strokeLog([(1, ga, 4), (1, gb, 4), (2, ga, 5), (2, gb, 4)]),
        seats: seats, course: .testPar72
    )
    let result = SkinsEngine.settle(state: state, config: SkinsConfig(unitStake: 3, carryOverTies: false))
    // With carry disabled, the tied hole is awarded immediately to the first ranked seat;
    // the next hole is then won by B, so the two players finish with one skin each.
    #expect(result.points(for: ga) == 1)
    #expect(result.points(for: gb) == 1)
    #expect(result.isZeroSum)
}

@Test("Bingo Bango Bongo scores all three event kinds on one hole")
func bingoAllKinds() {
    let state = RoundState(log: [
        ScoreEvent(id: UUID(), hole: 1, playerID: ga, payload: .holeEvent(.bingo), enteredBy: ga, sequence: 1),
        ScoreEvent(id: UUID(), hole: 1, playerID: ga, payload: .holeEvent(.bango), enteredBy: ga, sequence: 2),
        ScoreEvent(id: UUID(), hole: 1, playerID: gb, payload: .holeEvent(.bongo), enteredBy: ga, sequence: 3)
    ], seats: twoSeats(), course: .testPar72)
    let result = BingoBangoBongoEngine.settle(state: state, config: BingoBangoBongoConfig(unitStake: 2))
    #expect(result.points(for: ga) == 2)
    #expect(result.points(for: gb) == 1)
    #expect(result.money(for: ga) == 2)
    #expect(result.isZeroSum)
}
