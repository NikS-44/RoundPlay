import Testing
import Foundation
@testable import RoundPlayEngine

@Test("Fixture suite is present")
func fixturesExist() throws {
    let fixtures = try EngineFixture.loadAll()
    #expect(fixtures.count >= 3, "expected at least three fixtures, found \(fixtures.count)")
}

@Test("Every fixture settles to its recorded money")
func fixturesSettleAsRecorded() throws {
    for fixture in try EngineFixture.loadAll() {
        let state = RoundState(log: fixture.log, seats: fixture.seats, course: fixture.course)
        let result = try GameLibrary.settle(fixture.configuration, state: state)

        #expect(result.isZeroSum, "\(fixture.name) is not zero-sum")

        for expected in fixture.expected {
            guard let seat = fixture.seats.first(where: { $0.name == expected.playerName }) else {
                Issue.record("\(fixture.name): no seat named \(expected.playerName)")
                continue
            }
            #expect(
                result.points(for: seat.playerID) == expected.points,
                "\(fixture.name): \(expected.playerName) points"
            )
            #expect(
                result.money(for: seat.playerID) == Decimal(string: expected.money),
                "\(fixture.name): \(expected.playerName) money"
            )
        }
    }
}

@Test("Fixtures declare the engine version they were recorded against")
func fixturesDeclareVersion() throws {
    for fixture in try EngineFixture.loadAll() {
        #expect(
            fixture.engineVersion == RoundPlayEngineVersion.current,
            "\(fixture.name) was recorded against \(fixture.engineVersion) but the engine is now \(RoundPlayEngineVersion.current). Re-record it deliberately, or the rule change was a regression."
        )
    }
}
