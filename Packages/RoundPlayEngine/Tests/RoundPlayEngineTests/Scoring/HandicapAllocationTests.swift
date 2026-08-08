import Testing
@testable import RoundPlayEngine

@Test("Scratch player receives no strokes")
func scratchGetsNothing() {
    for si in 1...18 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 0, strokeIndex: si) == 0)
    }
}

@Test("A 12 handicap gets one stroke on the twelve hardest holes")
func twelveHandicapAllocation() {
    for si in 1...12 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 12, strokeIndex: si) == 1)
    }
    for si in 13...18 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 12, strokeIndex: si) == 0)
    }
}

@Test("A 22 handicap gets a second stroke on the four hardest holes")
func twentyTwoHandicapAllocation() {
    for si in 1...4 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 22, strokeIndex: si) == 2)
    }
    for si in 5...18 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 22, strokeIndex: si) == 1)
    }
}

@Test("Exactly 36 gives two strokes everywhere")
func thirtySixHandicapAllocation() {
    for si in 1...18 {
        #expect(HandicapAllocation.strokesReceived(courseHandicap: 36, strokeIndex: si) == 2)
    }
}

@Test("Total strokes allocated equals the course handicap")
func allocationSumsToHandicap() {
    for handicap in 0...54 {
        let total = (1...18).reduce(0) {
            $0 + HandicapAllocation.strokesReceived(courseHandicap: handicap, strokeIndex: $1)
        }
        #expect(total == handicap, "handicap \(handicap) allocated \(total) strokes")
    }
}

@Test("Plus handicaps are treated as scratch in Phase 1")
func plusHandicapsClampToScratch() {
    #expect(HandicapAllocation.strokesReceived(courseHandicap: -3, strokeIndex: 1) == 0)
}
