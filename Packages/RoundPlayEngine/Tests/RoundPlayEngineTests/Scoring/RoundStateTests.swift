import Testing
import Foundation
@testable import RoundPlayEngine

private let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000A11C")!
private let bob = UUID(uuidString: "00000000-0000-0000-0000-0000000000B0")!

private func seats() -> [Seat] {
    [
        Seat(playerID: alice, name: "Alice", courseHandicap: 0),
        Seat(playerID: bob, name: "Bob", courseHandicap: 18)
    ]
}

private func strokeEvent(
    hole: Int, player: UUID, strokes: Int, by: UUID, seq: Int
) -> ScoreEvent {
    ScoreEvent(
        id: UUID(), hole: hole, playerID: player,
        payload: .strokes(strokes), enteredBy: by, sequence: seq
    )
}

@Test("Latest event by sequence wins for a hole and player")
func latestEventWins() {
    let log = [
        strokeEvent(hole: 1, player: alice, strokes: 6, by: bob, seq: 1),
        strokeEvent(hole: 1, player: alice, strokes: 5, by: bob, seq: 2)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.gross(hole: 1, player: alice) == 5)
}

@Test("Out-of-order sequences still resolve to the highest")
func outOfOrderResolves() {
    let log = [
        strokeEvent(hole: 1, player: alice, strokes: 5, by: bob, seq: 9),
        strokeEvent(hole: 1, player: alice, strokes: 6, by: bob, seq: 2)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.gross(hole: 1, player: alice) == 5)
}

@Test("Net subtracts allocated handicap strokes")
func netAppliesHandicap() {
    // Hole 1 is stroke index 1; an 18 handicap gets a shot on every hole.
    let log = [
        strokeEvent(hole: 1, player: bob, strokes: 6, by: bob, seq: 1)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.gross(hole: 1, player: bob) == 6)
    #expect(state.strokesReceived(hole: 1, player: bob) == 1)
    #expect(state.net(hole: 1, player: bob) == 5)
}

@Test("A hole is complete only when every seat has a score")
func completenessRequiresAllSeats() {
    let log = [strokeEvent(hole: 1, player: alice, strokes: 4, by: alice, seq: 1)]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.isComplete(hole: 1) == false)

    let full = log + [strokeEvent(hole: 1, player: bob, strokes: 5, by: alice, seq: 2)]
    let complete = RoundState(log: full, seats: seats(), course: .testPar72)
    #expect(complete.isComplete(hole: 1) == true)
    #expect(complete.completedHoles(in: .total) == [1])
}

@Test("Wolf declarations and hole events resolve independently of strokes")
func nonStrokePayloadsResolve() {
    let log = [
        ScoreEvent(id: UUID(), hole: 3, playerID: alice,
                   payload: .wolfDeclaration(.partner(bob)), enteredBy: alice, sequence: 1),
        ScoreEvent(id: UUID(), hole: 3, playerID: bob,
                   payload: .holeEvent(.bingo), enteredBy: alice, sequence: 2)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.wolfDeclaration(hole: 3)?.wolf == alice)
    #expect(state.wolfDeclaration(hole: 3)?.declaration == .partner(bob))
    #expect(state.holeEventWinner(hole: 3, kind: .bingo) == bob)
    #expect(state.holeEventWinner(hole: 3, kind: .bango) == nil)
}
