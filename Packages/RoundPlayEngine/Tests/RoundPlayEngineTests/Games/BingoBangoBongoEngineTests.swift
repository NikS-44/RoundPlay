import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
private let b = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!

private func pair() -> [Seat] {
    [
        Seat(playerID: a, name: "Ann", courseHandicap: 0),
        Seat(playerID: b, name: "Ben", courseHandicap: 24)
    ]
}

private func eventLog(_ entries: [(hole: Int, player: UUID, kind: HoleEventKind)]) -> [ScoreEvent] {
    entries.enumerated().map { index, entry in
        ScoreEvent(id: UUID(), hole: entry.hole, playerID: entry.player,
                   payload: .holeEvent(entry.kind), enteredBy: a, sequence: index + 1)
    }
}

@Test("Each recorded event is worth one point")
func eventsScorePoints() {
    let state = RoundState(
        log: eventLog([
            (1, a, .bingo), (1, b, .bango), (1, a, .bongo)
        ]),
        seats: pair(), course: .testPar72
    )
    let result = BingoBangoBongoEngine.settle(
        state: state, config: BingoBangoBongoConfig(unitStake: 1)
    )

    #expect(result.points(for: a) == 2)
    #expect(result.points(for: b) == 1)
    #expect(result.money(for: a) == 1)
    #expect(result.money(for: b) == -1)
    #expect(result.isZeroSum)
}

@Test("Points are independent of stroke counts, so a high handicap can win")
func handicapIsIrrelevant() {
    // Ben is a 24 handicap and takes more strokes, but reaches the green first every time.
    var log = eventLog([
        (1, b, .bingo), (1, b, .bango), (1, b, .bongo),
        (2, b, .bingo), (2, b, .bango), (2, b, .bongo)
    ])
    log.append(ScoreEvent(id: UUID(), hole: 1, playerID: a,
                          payload: .strokes(3), enteredBy: a, sequence: 100))
    log.append(ScoreEvent(id: UUID(), hole: 1, playerID: b,
                          payload: .strokes(8), enteredBy: a, sequence: 101))

    let state = RoundState(log: log, seats: pair(), course: .testPar72)
    let result = BingoBangoBongoEngine.settle(
        state: state, config: BingoBangoBongoConfig(unitStake: 2)
    )

    #expect(result.points(for: b) == 6)
    #expect(result.points(for: a) == 0)
    #expect(result.money(for: b) == 12)
    #expect(result.isZeroSum)
}

@Test("A rewritten event replaces the earlier winner")
func laterEventOverwrites() {
    let log = [
        ScoreEvent(id: UUID(), hole: 1, playerID: a,
                   payload: .holeEvent(.bingo), enteredBy: a, sequence: 1),
        ScoreEvent(id: UUID(), hole: 1, playerID: b,
                   payload: .holeEvent(.bingo), enteredBy: a, sequence: 2)
    ]
    let state = RoundState(log: log, seats: pair(), course: .testPar72)
    let result = BingoBangoBongoEngine.settle(
        state: state, config: BingoBangoBongoConfig(unitStake: 1)
    )

    #expect(result.points(for: b) == 1)
    #expect(result.points(for: a) == 0)
}

@Test("Holes with no events recorded score nothing")
func missingEventsScoreNothing() {
    let state = RoundState(log: [], seats: pair(), course: .testPar72)
    let result = BingoBangoBongoEngine.settle(
        state: state, config: BingoBangoBongoConfig(unitStake: 1)
    )

    #expect(result.standings.allSatisfy { $0.points == 0 && $0.money == 0 })
    #expect(result.isZeroSum)
}
