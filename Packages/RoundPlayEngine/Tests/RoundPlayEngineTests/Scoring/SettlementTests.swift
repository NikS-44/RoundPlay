import Testing
import Foundation
@testable import RoundPlayEngine

private let a = UUID(), b = UUID(), c = UUID()

@Test("A balanced settlement is zero-sum")
func balancedIsZeroSum() {
    let settlement = Settlement(
        gameType: .skins,
        standings: [
            PlayerStanding(playerID: a, points: 2, money: 10),
            PlayerStanding(playerID: b, points: 0, money: -10)
        ],
        holeExplanations: []
    )
    #expect(settlement.isZeroSum)
    #expect(settlement.money(for: a) == 10)
    #expect(settlement.money(for: c) == 0)
}

@Test("An unbalanced settlement is caught")
func unbalancedIsDetected() {
    let settlement = Settlement(
        gameType: .skins,
        standings: [
            PlayerStanding(playerID: a, points: 2, money: 10),
            PlayerStanding(playerID: b, points: 0, money: -5)
        ],
        holeExplanations: []
    )
    #expect(settlement.isZeroSum == false)
}

@Test("Point-difference settlement pays each pair the unit stake per point")
func pointDifferenceSettles() {
    // a: 10 pts, b: 6 pts, c: 2 pts. At $1/point:
    // a collects (10-6) + (10-2) = 12; b collects (6-10) + (6-2) = 0; c: (2-10)+(2-6) = -12
    let money = Settlement.pointDifferenceMoney(
        points: [a: 10, b: 6, c: 2],
        unitStake: 1
    )
    #expect(money[a] == 12)
    #expect(money[b] == 0)
    #expect(money[c] == -12)
    #expect(money.values.reduce(0, +) == 0)
}
