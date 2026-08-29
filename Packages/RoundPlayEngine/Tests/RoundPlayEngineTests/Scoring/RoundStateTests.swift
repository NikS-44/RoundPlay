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

@Test("Later recordedAt wins even when sequence is lower")
func laterRecordedAtWinsAcrossDevices() {
    let earlier = ScoreEvent(
        id: UUID(), hole: 1, playerID: alice, payload: .strokes(6),
        enteredBy: bob, sequence: 20,
        recordedAt: Date(timeIntervalSince1970: 100)
    )
    let later = ScoreEvent(
        id: UUID(), hole: 1, playerID: alice, payload: .strokes(5),
        enteredBy: alice, sequence: 1,
        recordedAt: Date(timeIntervalSince1970: 200)
    )
    let state = RoundState(log: [earlier, later], seats: seats(), course: .testPar72)
    #expect(state.gross(hole: 1, player: alice) == 5)
}

@Test("Identical recordedAt breaks ties by event id, stably")
func identicalRecordedAtIsDeterministic() {
    let lowID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
    let highID = UUID(uuidString: "81000000-0000-0000-0000-000000000002")!
    let instant = Date(timeIntervalSince1970: 50)
    let events = [
        ScoreEvent(id: highID, hole: 1, playerID: alice, payload: .strokes(6),
                   enteredBy: alice, sequence: 1, recordedAt: instant),
        ScoreEvent(id: lowID, hole: 1, playerID: alice, payload: .strokes(5),
                   enteredBy: alice, sequence: 1, recordedAt: instant)
    ]
    #expect(RoundState(log: events, seats: seats(), course: .testPar72).gross(hole: 1, player: alice) == 6)
    #expect(RoundState(log: events.reversed(), seats: seats(), course: .testPar72).gross(hole: 1, player: alice) == 6)
}

@Test("Union of two logs matches folding the superset")
func mergeSupersetMatchesFoldingSuperset() {
    let shared = [
        strokeEvent(hole: 1, player: alice, strokes: 4, by: alice, seq: 1),
        strokeEvent(hole: 1, player: bob, strokes: 5, by: alice, seq: 2)
    ]
    let extra = strokeEvent(hole: 2, player: alice, strokes: 3, by: bob, seq: 3)
    let union = shared + [extra]
    let fromUnion = RoundState(log: shared + [extra], seats: seats(), course: .testPar72)
    let fromSuperset = RoundState(log: union, seats: seats(), course: .testPar72)
    #expect(fromUnion.gross(hole: 1, player: alice) == fromSuperset.gross(hole: 1, player: alice))
    #expect(fromUnion.gross(hole: 2, player: alice) == 3)
}

@Test("Union of disjoint hole logs reflects both devices")
func mergeDisjointHoles() {
    let phone = [strokeEvent(hole: 1, player: alice, strokes: 4, by: alice, seq: 1)]
    let watch = [strokeEvent(hole: 2, player: bob, strokes: 6, by: bob, seq: 1)]
    let state = RoundState(log: phone + watch, seats: seats(), course: .testPar72)
    #expect(state.gross(hole: 1, player: alice) == 4)
    #expect(state.gross(hole: 2, player: bob) == 6)
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

@Test("A clear-strokes event removes a score without deleting audit history")
func clearStrokesRemovesCurrentValue() {
    let log = [
        strokeEvent(hole: 1, player: alice, strokes: 5, by: alice, seq: 1),
        ScoreEvent(id: UUID(), hole: 1, playerID: alice, payload: .clearStrokes, enteredBy: alice, sequence: 2)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.gross(hole: 1, player: alice) == nil)
    #expect(state.isComplete(hole: 1) == false)
}

@Test("A clear hole-event event removes its current winner")
func clearHoleEventRemovesCurrentWinner() {
    let log = [
        ScoreEvent(id: UUID(), hole: 1, playerID: alice,
                   payload: .holeEvent(.bingo), enteredBy: alice, sequence: 1),
        ScoreEvent(id: UUID(), hole: 1, playerID: alice,
                   payload: .clearHoleEvent(.bingo), enteredBy: alice, sequence: 2)
    ]
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.holeEventWinner(hole: 1, kind: .bingo) == nil)
}

// MARK: - Current hole

/// Scores every player on `holes`, so those holes read as complete.
private func completing(_ holes: [Int]) -> [ScoreEvent] {
    var log: [ScoreEvent] = []
    var seq = 0
    for hole in holes {
        for player in [alice, bob] {
            seq += 1
            log.append(strokeEvent(hole: hole, player: player, strokes: 4, by: alice, seq: seq))
        }
    }
    return log
}

@Test("An unstarted round is on the segment's first hole")
func currentHoleOnFreshRound() {
    let state = RoundState(log: [], seats: seats(), course: .testPar72)
    #expect(state.currentHole(in: .total) == 1)
}

@Test("The current hole is the first one still missing a score")
func currentHoleSkipsCompletedHoles() {
    let state = RoundState(log: completing(Array(1...6)), seats: seats(), course: .testPar72)
    #expect(state.currentHole(in: .total) == 7)
}

@Test("A hole scored for only some players is still the current hole")
func currentHoleWaitsForEveryPlayer() {
    var log = completing(Array(1...2))
    log.append(strokeEvent(hole: 3, player: alice, strokes: 4, by: alice, seq: 99))
    let state = RoundState(log: log, seats: seats(), course: .testPar72)
    #expect(state.currentHole(in: .total) == 3)
}

@Test("A finished round stays on the segment's last hole")
func currentHoleOnCompleteRound() {
    let state = RoundState(log: completing(Array(1...18)), seats: seats(), course: .testPar72)
    #expect(state.currentHole(in: .total) == 18)
}

@Test("A back-nine round starts on hole 10, not hole 1")
func currentHoleRespectsBackNine() {
    let state = RoundState(log: [], seats: seats(), course: .testPar72)
    #expect(state.currentHole(in: .back) == 10)
}

@Test("A back-nine round advances within its own holes")
func currentHoleAdvancesWithinBackNine() {
    let state = RoundState(log: completing([10, 11, 12]), seats: seats(), course: .testPar72)
    #expect(state.currentHole(in: .back) == 13)
}

@Test("Holes completed outside the segment do not move the current hole")
func currentHoleIgnoresHolesOutsideSegment() {
    let state = RoundState(log: completing(Array(1...9)), seats: seats(), course: .testPar72)
    #expect(state.currentHole(in: .back) == 10)
}
