import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
private let b = UUID(uuidString: "50000000-0000-0000-0000-000000000002")!

private func singles() -> [Seat] {
    [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 0)
    ]
}

/// `aScores` and `bScores` are indexed from hole 1.
private func log(aScores: [Int: Int], bScores: [Int: Int]) -> [ScoreEvent] {
    var events: [ScoreEvent] = []
    var seq = 0
    for hole in Set(aScores.keys).union(bScores.keys).sorted() {
        if let s = aScores[hole] {
            seq += 1
            events.append(ScoreEvent(id: UUID(), hole: hole, playerID: a,
                                     payload: .strokes(s), enteredBy: a, sequence: seq))
        }
        if let s = bScores[hole] {
            seq += 1
            events.append(ScoreEvent(id: UUID(), hole: hole, playerID: b,
                                     payload: .strokes(s), enteredBy: a, sequence: seq))
        }
    }
    return events
}

/// Ann wins holes 1–3, everything else halved.
private func annWinsFrontThree() -> [ScoreEvent] {
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 {
        aScores[hole] = 4
        bScores[hole] = (1...3).contains(hole) ? 5 : 4
    }
    return log(aScores: aScores, bScores: bScores)
}

@Test("Winning the front nine pays one unit")
func frontNinePays() throws {
    let state = RoundState(log: annWinsFrontThree(), seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state,
        config: NassauConfig(unitStake: 10, automaticPressAt: nil)
    )
    // Ann wins front (3 up) and total (3 up); back nine is all square and pays nothing.
    #expect(result.money(for: a) == 20)
    #expect(result.money(for: b) == -20)
    #expect(result.isZeroSum)
}

@Test("An all-square segment pays nothing")
func allSquarePaysNothing() throws {
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 4 }
    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state, config: NassauConfig(unitStake: 10, automaticPressAt: nil)
    )

    #expect(result.money(for: a) == 0)
    #expect(result.money(for: b) == 0)
}

@Test("Net scoring decides holes when handicaps differ")
func netDecidesHoles() throws {
    let seats = [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 18)
    ]
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 5 }   // Ben nets 4 everywhere
    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: seats, course: .testPar72)
    let result = try NassauEngine.settle(
        state: state, config: NassauConfig(unitStake: 10, automaticPressAt: nil)
    )

    #expect(result.money(for: a) == 0)   // every hole halved on net
}

@Test("An automatic press opens a second bet on the remaining holes")
func automaticPressOpens() throws {
    // Ann wins holes 1 and 2 → Ben is 2 down after hole 2 → press opens for holes 3–9.
    // Ben then wins holes 3, 4 and 5; the rest of the front is halved.
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 4 }
    bScores[1] = 5; bScores[2] = 5
    aScores[3] = 5; aScores[4] = 5; aScores[5] = 5

    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state, config: NassauConfig(unitStake: 10, automaticPressAt: 2)
    )

    // Front nine original bet: Ann 2 up then Ben wins 3 → Ben 1 up → Ben collects 10.
    // Press (holes 3–9): Ben 3 up → Ben collects 10.
    // Back nine: all square → nothing.
    // Total 18: Ben 1 up → Ben collects 10.
    #expect(result.money(for: b) == 30)
    #expect(result.money(for: a) == -30)
    #expect(result.isZeroSum)
    #expect(result.holeExplanations.contains { $0.text.lowercased().contains("press") })
}

@Test("Nassau rejects anything other than two players in Phase 1")
func requiresTwoPlayers() {
    let seats = singles() + [Seat(playerID: UUID(), name: "Cal", courseHandicap: 0)]
    let state = RoundState(log: [], seats: seats, course: .testPar72)
    #expect(throws: NassauEngine.SettleError.requiresTwoPlayers) {
        try NassauEngine.settle(state: state, config: NassauConfig(unitStake: 1, automaticPressAt: nil))
    }
}
