import Testing
import Foundation
@testable import RoundPlayEngine

private let low = UUID(uuidString: "00000000-0000-0000-0000-00000000010A")!
private let high = UUID(uuidString: "00000000-0000-0000-0000-00000000021B")!
private let mid = UUID(uuidString: "00000000-0000-0000-0000-00000000032C")!

private func pair(lowHandicap: Int, highHandicap: Int) -> [Seat] {
    [
        Seat(playerID: low, name: "Low", courseHandicap: lowHandicap),
        Seat(playerID: high, name: "High", courseHandicap: highHandicap)
    ]
}

// MARK: - Modes

@Test("Off the low gives the difference to everyone above the lowest handicap")
func offTheLowUsesDifference() {
    let handicaps = PlayingHandicap.byPlayer(
        seats: pair(lowHandicap: 4, highHandicap: 10),
        settings: HandicapSettings(mode: .offTheLow)
    )
    #expect(handicaps[low] == 0)
    #expect(handicaps[high] == 6)
}

@Test("Full mode leaves every handicap untouched")
func fullModeKeepsHandicaps() {
    let handicaps = PlayingHandicap.byPlayer(
        seats: pair(lowHandicap: 4, highHandicap: 10),
        settings: HandicapSettings(mode: .full)
    )
    #expect(handicaps[low] == 4)
    #expect(handicaps[high] == 10)
}

@Test("Straight up zeroes everyone regardless of allowance or cap")
func straightUpZeroesEveryone() {
    let handicaps = PlayingHandicap.byPlayer(
        seats: pair(lowHandicap: 4, highHandicap: 30),
        settings: HandicapSettings(mode: .straightUp, allowancePercent: 85, maxStrokes: 18)
    )
    #expect(handicaps[low] == 0)
    #expect(handicaps[high] == 0)
}

/// The reason this feature exists. Full handicaps and off-the-low are *not* interchangeable for
/// hole-by-hole games: strokes land in stroke-index order, so subtracting the low handicap moves
/// which holes carry an edge.
@Test("Full and off-the-low differ on a hole where both players would otherwise get a stroke")
func fullAndOffTheLowDivergeByStrokeIndex() {
    let seats = pair(lowHandicap: 4, highHandicap: 10)
    let course = Course.testPar72
    let strokeIndexThree = course.holes.first { $0.strokeIndex == 3 }!.number

    let full = RoundState(
        log: [], seats: seats, course: course,
        handicapSettings: HandicapSettings(mode: .full)
    )
    // Both inside a handicap of 4 and 10, so neither gains an edge.
    #expect(full.strokesReceived(hole: strokeIndexThree, player: low) == 1)
    #expect(full.strokesReceived(hole: strokeIndexThree, player: high) == 1)

    let offLow = RoundState(
        log: [], seats: seats, course: course,
        handicapSettings: HandicapSettings(mode: .offTheLow)
    )
    // High plays off 6, so stroke index 3 is theirs alone.
    #expect(offLow.strokesReceived(hole: strokeIndexThree, player: low) == 0)
    #expect(offLow.strokesReceived(hole: strokeIndexThree, player: high) == 1)
}

// MARK: - Allowance

@Test("Allowance scales the course handicap and rounds to whole strokes")
func allowanceRoundsToWholeStrokes() {
    let handicaps = PlayingHandicap.byPlayer(
        seats: pair(lowHandicap: 10, highHandicap: 21),
        settings: HandicapSettings(mode: .full, allowancePercent: 85)
    )
    #expect(handicaps[low] == 9)    // 8.5 rounds up
    #expect(handicaps[high] == 18)  // 17.85 rounds up
}

@Test("Allowance applies before the low handicap is subtracted")
func allowanceAppliesBeforeOffTheLow() {
    let handicaps = PlayingHandicap.byPlayer(
        seats: pair(lowHandicap: 10, highHandicap: 20),
        settings: HandicapSettings(mode: .offTheLow, allowancePercent: 50)
    )
    // 5 and 10 after allowance, so the difference is 5 — not 50% of the raw 10-shot gap by
    // coincidence, which is what applying the allowance afterwards would give.
    #expect(handicaps[low] == 0)
    #expect(handicaps[high] == 5)
}

// MARK: - Cap

@Test("Cap limits the playing handicap before the low handicap is subtracted")
func capAppliesToPlayingHandicap() {
    let handicaps = PlayingHandicap.byPlayer(
        seats: pair(lowHandicap: 4, highHandicap: 36),
        settings: HandicapSettings(mode: .offTheLow, maxStrokes: 18)
    )
    // High caps at 18, then gives up the low player's 4.
    #expect(handicaps[low] == 0)
    #expect(handicaps[high] == 14)
}

@Test("A cap below every handicap leaves the group level")
func capBelowEveryoneLevelsTheField() {
    let handicaps = PlayingHandicap.byPlayer(
        seats: pair(lowHandicap: 12, highHandicap: 30),
        settings: HandicapSettings(mode: .offTheLow, maxStrokes: 8)
    )
    #expect(handicaps[low] == 0)
    #expect(handicaps[high] == 0)
}

// MARK: - Edge cases

@Test("Plus handicaps clamp to zero rather than handing strokes back")
func plusHandicapsClampToZero() {
    let handicaps = PlayingHandicap.byPlayer(
        seats: pair(lowHandicap: -3, highHandicap: 9),
        settings: HandicapSettings(mode: .offTheLow)
    )
    #expect(handicaps[low] == 0)
    #expect(handicaps[high] == 9)
}

@Test("Three players all measure against the single lowest handicap")
func threePlayersShareOneBaseline() {
    let seats = [
        Seat(playerID: low, name: "Low", courseHandicap: 6),
        Seat(playerID: mid, name: "Mid", courseHandicap: 12),
        Seat(playerID: high, name: "High", courseHandicap: 20)
    ]
    let handicaps = PlayingHandicap.byPlayer(seats: seats, settings: HandicapSettings(mode: .offTheLow))
    #expect(handicaps[low] == 0)
    #expect(handicaps[mid] == 6)
    #expect(handicaps[high] == 14)
}

@Test("Everyone on the same handicap plays level under off the low")
func equalHandicapsPlayLevel() {
    let handicaps = PlayingHandicap.byPlayer(
        seats: pair(lowHandicap: 14, highHandicap: 14),
        settings: HandicapSettings(mode: .offTheLow)
    )
    #expect(handicaps[low] == 0)
    #expect(handicaps[high] == 0)
}

@Test("Straight up removes strokes from the scorecard entirely")
func straightUpRemovesStrokesFromHoles() {
    let course = Course.testPar72
    let state = RoundState(
        log: [], seats: pair(lowHandicap: 4, highHandicap: 28), course: course,
        handicapSettings: HandicapSettings(mode: .straightUp)
    )
    for hole in course.holes {
        #expect(state.strokesReceived(hole: hole.number, player: high) == 0)
    }
}
