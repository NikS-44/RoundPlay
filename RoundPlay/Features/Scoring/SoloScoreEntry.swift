import SwiftUI
import RoundPlayEngine
import RoundPlayData

/// Score-against-par arithmetic, in one place because three screens do it and they must agree.
///
/// Every total covers only the holes that actually have a score. Summing par across the whole
/// segment while gross covers four holes reports a course record instead of a short round — the
/// bug `RoundSummaryView.finalScores` already had to fix once.
enum RelativeToPar {
    static func holesPlayed(state: RoundState, playerID: UUID, holes: ClosedRange<Int>) -> Int {
        holes.count { state.gross(hole: $0, player: playerID) != nil }
    }

    static func grossVersusPar(state: RoundState, course: Course, playerID: UUID, holes: ClosedRange<Int>) -> Int {
        holes.reduce(0) { total, hole in
            guard let gross = state.gross(hole: hole, player: playerID) else { return total }
            return total + gross - (course.hole(hole)?.par ?? 0)
        }
    }

    /// "E", "+2", "-3" — the scoreboard convention, not a signed integer.
    static func label(_ value: Int) -> String {
        if value == 0 { return "E" }
        return value > 0 ? "+\(value)" : "\(value)"
    }
}

/// Score entry for a one-seat round.
///
/// No name row, no team badge, no stroke eyebrow, no declaration prompts — with one player each of
/// them is either constant or empty, and the whole screen goes to the grid instead.
struct SoloScoreEntry: View {
    let seat: SeatRecord
    let course: Course
    let hole: Int
    let state: RoundState
    let onRecord: (Int) -> Void

    var body: some View {
        ScoreGridView(
            par: course.hole(hole)?.par ?? 4,
            strokesReceived: state.strokesReceived(hole: hole, player: seat.playerID),
            selected: state.gross(hole: hole, player: seat.playerID),
            onSelect: onRecord
        )
    }
}
