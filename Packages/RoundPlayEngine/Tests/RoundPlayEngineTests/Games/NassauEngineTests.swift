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

/// Ann wins holes 1 and 2 and nothing else is played yet, so Ben is 2 down standing on the third
/// tee — the moment the press question is live.
private func annWinsFirstTwo() -> [ScoreEvent] {
    log(aScores: [1: 4, 2: 4], bScores: [1: 5, 2: 5])
}

private func press(_ decision: PressDecision, hole: Int, by player: UUID, sequence: Int) -> ScoreEvent {
    ScoreEvent(id: UUID(), hole: hole, playerID: player,
               payload: .press(decision), enteredBy: player, sequence: sequence)
}

@Test("Winning the front nine pays one unit")
func frontNinePays() throws {
    let state = RoundState(log: annWinsFrontThree(), seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state,
        config: NassauConfig(unitStake: 10, pressAt: nil)
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
        state: state, config: NassauConfig(unitStake: 10, pressAt: nil)
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
        state: state, config: NassauConfig(unitStake: 10, pressAt: nil)
    )

    #expect(result.money(for: a) == 0)   // every hole halved on net
}

// MARK: - Presses

@Test("Going two down puts the press to the side that's behind")
func pressIsOffered() {
    let state = RoundState(log: annWinsFirstTwo(), seats: singles(), course: .testPar72)
    let offer = NassauEngine.pressOffer(state: state, config: NassauConfig(unitStake: 10, pressAt: 2))

    #expect(offer?.hole == 3)
    #expect(offer?.throughHole == 9)
    #expect(offer?.segment == .front)
    #expect(offer?.trailingPlayerID == b)
    #expect(offer?.leadingPlayerID == a)
    #expect(offer?.holesDown == 2)
    #expect(offer?.stake == 10)
}

@Test("Nothing is offered until the deficit reaches the trigger")
func noOfferBeforeTrigger() {
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 4 }
    bScores[1] = 5      // Ben 1 down only

    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: singles(), course: .testPar72)
    #expect(NassauEngine.pressOffer(state: state,
                                    config: NassauConfig(unitStake: 10, pressAt: 2)) == nil)
}

@Test("Turning presses off never asks")
func pressesOffNeverAsks() {
    let state = RoundState(log: annWinsFirstTwo(), seats: singles(), course: .testPar72)
    #expect(NassauEngine.pressOffer(state: state,
                                    config: NassauConfig(unitStake: 10, pressAt: nil)) == nil)
}

@Test("An offer nobody has answered adds no money")
func unansweredOfferCostsNothing() throws {
    // Ann wins 1 and 2, Ben wins 3, 4 and 5 — the same scores as the accepted-press case below,
    // with no answer recorded. Only the three original bets should settle.
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 4 }
    bScores[1] = 5; bScores[2] = 5
    aScores[3] = 5; aScores[4] = 5; aScores[5] = 5

    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state, config: NassauConfig(unitStake: 10, pressAt: 2)
    )

    // Front: Ben 1 up → 10. Back: square → 0. Total: Ben 1 up → 10. No press bet.
    #expect(result.money(for: b) == 20)
    #expect(result.isZeroSum)
}

@Test("Taking the press opens a second bet on the remaining holes")
func acceptedPressOpensBet() throws {
    // Ann wins holes 1 and 2 → Ben is 2 down after hole 2 and presses for holes 3–9.
    // Ben then wins holes 3, 4 and 5; the rest of the front is halved.
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 4 }
    bScores[1] = 5; bScores[2] = 5
    aScores[3] = 5; aScores[4] = 5; aScores[5] = 5

    let events = log(aScores: aScores, bScores: bScores)
        + [press(.accepted, hole: 3, by: b, sequence: 1_000)]
    let state = RoundState(log: events, seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state, config: NassauConfig(unitStake: 10, pressAt: 2)
    )

    // Front nine original bet: Ann 2 up then Ben wins 3 → Ben 1 up → Ben collects 10.
    // Press (holes 3–9): Ben 3 up → Ben collects 10.
    // Back nine: all square → nothing.
    // Total 18: Ben 1 up → Ben collects 10.
    #expect(result.money(for: b) == 30)
    #expect(result.money(for: a) == -30)
    #expect(result.isZeroSum)
    #expect(result.holeExplanations.contains { $0.text.contains("pressed") })
}

@Test("Passing on the press adds no bet and is recorded in the narration")
func declinedPressOpensNothing() throws {
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...18 { aScores[hole] = 4; bScores[hole] = 4 }
    bScores[1] = 5; bScores[2] = 5
    aScores[3] = 5; aScores[4] = 5; aScores[5] = 5

    let events = log(aScores: aScores, bScores: bScores)
        + [press(.declined, hole: 3, by: b, sequence: 1_000)]
    let state = RoundState(log: events, seats: singles(), course: .testPar72)
    let result = try NassauEngine.settle(
        state: state, config: NassauConfig(unitStake: 10, pressAt: 2)
    )

    #expect(result.money(for: b) == 20)   // front + total only
    #expect(result.holeExplanations.contains { $0.text.contains("passed on the press") })
}

@Test("A pass at two down doesn't silence the offer at three down")
func deeperDeficitAsksAgain() {
    // Ann wins 1, 2 and 3. Ben passes at 2 down; by hole 4 he's 3 down and gets asked again.
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...3 { aScores[hole] = 4; bScores[hole] = 5 }

    let events = log(aScores: aScores, bScores: bScores)
        + [press(.declined, hole: 3, by: b, sequence: 1_000)]
    let state = RoundState(log: events, seats: singles(), course: .testPar72)
    let offer = NassauEngine.pressOffer(state: state, config: NassauConfig(unitStake: 10, pressAt: 2))

    #expect(offer?.hole == 4)
    #expect(offer?.holesDown == 3)
}

@Test("A pass is not re-asked at the same deficit")
func samedDeficitDoesNotAskAgain() {
    // Ann wins 1 and 2, hole 3 is halved — Ben is still exactly 2 down, and has already passed.
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...3 { aScores[hole] = 4; bScores[hole] = hole <= 2 ? 5 : 4 }

    let events = log(aScores: aScores, bScores: bScores)
        + [press(.declined, hole: 3, by: b, sequence: 1_000)]
    let state = RoundState(log: events, seats: singles(), course: .testPar72)

    #expect(NassauEngine.pressOffer(state: state,
                                    config: NassauConfig(unitStake: 10, pressAt: 2)) == nil)
}

@Test("Playing on without answering lapses the offer rather than repeating it")
func unansweredOfferLapses() {
    // 2 down after hole 2, hole 3 played with no answer, still 2 down → no offer on hole 4.
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...3 { aScores[hole] = 4; bScores[hole] = hole <= 2 ? 5 : 4 }

    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: singles(), course: .testPar72)
    #expect(NassauEngine.pressOffer(state: state,
                                    config: NassauConfig(unitStake: 10, pressAt: 2)) == nil)
}

@Test("The back nine gets its own press question")
func backNinePressesSeparately() {
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...11 { aScores[hole] = 4; bScores[hole] = 4 }
    bScores[10] = 5; bScores[11] = 5     // Ben 2 down on the back after hole 11

    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: singles(), course: .testPar72)
    let offer = NassauEngine.pressOffer(state: state, config: NassauConfig(unitStake: 10, pressAt: 2))

    #expect(offer?.segment == .back)
    #expect(offer?.hole == 12)
    #expect(offer?.throughHole == 18)
}

@Test("No press is offered on the last hole of a nine")
func noPressWithNoHolesLeft() {
    // Ben goes 2 down for the first time on hole 9 — there is nothing left of the front to press.
    var aScores: [Int: Int] = [:], bScores: [Int: Int] = [:]
    for hole in 1...9 { aScores[hole] = 4; bScores[hole] = 4 }
    bScores[8] = 5; bScores[9] = 5

    let state = RoundState(log: log(aScores: aScores, bScores: bScores),
                           seats: singles(), course: .testPar72)
    #expect(NassauEngine.pressOffer(state: state,
                                    config: NassauConfig(unitStake: 10, pressAt: 2)) == nil)
}

@Test("Nassau rejects anything other than two players in Phase 1")
func requiresTwoPlayers() {
    let seats = singles() + [Seat(playerID: UUID(), name: "Cal", courseHandicap: 0)]
    let state = RoundState(log: [], seats: seats, course: .testPar72)
    #expect(throws: NassauEngine.SettleError.requiresTwoPlayers) {
        try NassauEngine.settle(state: state, config: NassauConfig(unitStake: 1, pressAt: nil))
    }
}

@Test("Rounds stored before presses needed consent still carry their threshold")
func decodesLegacyConfigKey() throws {
    let stored = #"{"unitStake":10,"automaticPressAt":2}"#.data(using: .utf8)!
    let config = try JSONDecoder().decode(NassauConfig.self, from: stored)

    #expect(config.pressAt == 2)
    #expect(config.unitStake == 10)
}
