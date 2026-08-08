import Foundation

/// Distributes a course handicap across 18 holes by stroke index.
///
/// The rule every scorecard uses: a handicap of 12 means one stroke on the twelve hardest holes
/// (stroke index 1–12). Above 18 it wraps — a 22 gets one stroke everywhere plus a second on
/// stroke index 1–4.
///
/// **Plus handicaps (better than scratch) are out of scope for Phase 1** and clamp to zero.
/// They are a fraction of a percent of golfers and the convention for giving strokes back is not
/// uniform across clubs; guessing it would silently produce wrong money. Revisit with a real
/// plus-handicap tester.
public enum HandicapAllocation {
    public static let holeCount = 18

    public static func strokesReceived(courseHandicap: Int, strokeIndex: Int) -> Int {
        guard courseHandicap > 0 else { return 0 }
        let base = courseHandicap / holeCount
        let remainder = courseHandicap % holeCount
        return base + (strokeIndex <= remainder ? 1 : 0)
    }
}
