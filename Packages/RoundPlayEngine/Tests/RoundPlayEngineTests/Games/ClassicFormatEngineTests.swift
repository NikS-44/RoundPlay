import Testing
import Foundation
@testable import RoundPlayEngine

private let ca = UUID(uuidString: "85000000-0000-0000-0000-000000000001")!
private let cb = UUID(uuidString: "85000000-0000-0000-0000-000000000002")!
private let cc = UUID(uuidString: "85000000-0000-0000-0000-000000000003")!
private let cd = UUID(uuidString: "85000000-0000-0000-0000-000000000004")!

private func seats(_ ids: [UUID]) -> [Seat] { ids.enumerated().map { Seat(playerID: $0.element, name: "P\($0.offset + 1)", courseHandicap: 0) } }
private func log(_ scores: [(Int, UUID, Int)]) -> [ScoreEvent] {
    scores.enumerated().map { i, item in
        ScoreEvent(id: UUID(), hole: item.0, playerID: item.1, payload: .strokes(item.2), enteredBy: ca, sequence: i + 1)
    }
}

@Test("Stroke play totals net scores and has no money by default")
func strokePlayTotals() {
    let state = RoundState(log: log([(1, ca, 4), (1, cb, 5), (2, ca, 4), (2, cb, 6)]), seats: seats([ca, cb]), course: .testPar72)
    let result = StrokePlayEngine.settle(state: state, config: StrokePlayConfig(scoreType: .gross))
    #expect(result.points(for: ca) == 8)
    #expect(result.points(for: cb) == 11)
    #expect(result.money(for: ca) == 0)
}

@Test("Match play awards one stake to the match winner")
func matchPlaySettles() throws {
    let state = RoundState(log: log([(1, ca, 3), (1, cb, 4), (2, ca, 5), (2, cb, 4)]), seats: seats([ca, cb]), course: .testPar72)
    let result = try MatchPlayEngine.settle(state: state, config: MatchPlayConfig(unitStake: 10))
    #expect(result.points(for: ca) == 0)
    #expect(result.money(for: ca) == 0)
    #expect(result.isZeroSum)
}

@Test("Best ball compares the lowest net score for each two-person team")
func bestBallSettlesTeams() throws {
    let ids = [ca, cb, cc, cd]
    let state = RoundState(log: log([
        (1, ca, 3), (1, cb, 8), (1, cc, 4), (1, cd, 5)
    ]), seats: seats(ids), course: .testPar72)
    let result = try BestBallEngine.settle(state: state, config: BestBallConfig(unitStake: 2, teamASeatPositions: [0, 1]))
    #expect(result.points(for: ca) == 1)
    #expect(result.points(for: cc) == 0)
    #expect(result.money(for: ca) == 2)
    #expect(result.money(for: cc) == -2)
    #expect(result.isZeroSum)
}
