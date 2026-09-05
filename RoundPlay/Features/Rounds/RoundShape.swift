import Foundation
import RoundPlayEngine

/// How a round actually went, hole by hole — the breakdown that replaces money on a solo summary.
///
/// Derived entirely from scores already in the event log. Nothing here is stored.
struct RoundShape: Equatable {
    struct HoleResult: Equatable {
        let hole: Int
        let versusPar: Int
    }

    var eaglesOrBetter = 0
    var birdies = 0
    var pars = 0
    var bogeys = 0
    var doubles = 0
    var worse = 0
    var best: HoleResult?
    var worst: HoleResult?

    /// Only the rows worth printing. An all-par round shouldn't list five zeroes.
    var counts: [(label: String, count: Int)] {
        [
            ("Eagles", eaglesOrBetter),
            ("Birdies", birdies),
            ("Pars", pars),
            ("Bogeys", bogeys),
            ("Doubles", doubles),
            ("Worse", worse),
        ].filter { $0.count > 0 }
    }

    /// Gross against par, not net — the summary shows both, and the distribution people mean when
    /// they say "three birdies" is always the gross one.
    static func of(state: RoundState, course: Course, playerID: UUID, holes: ClosedRange<Int>) -> RoundShape {
        var shape = RoundShape()
        for hole in holes {
            guard let gross = state.gross(hole: hole, player: playerID),
                  let par = course.hole(hole)?.par
            else { continue }
            let versusPar = gross - par
            switch versusPar {
            case ...(-2): shape.eaglesOrBetter += 1
            case -1: shape.birdies += 1
            case 0: shape.pars += 1
            case 1: shape.bogeys += 1
            case 2: shape.doubles += 1
            default: shape.worse += 1
            }
            // Ties keep the earlier hole: the first time you made that score is the one you remember.
            if shape.best.map({ versusPar < $0.versusPar }) ?? true {
                shape.best = HoleResult(hole: hole, versusPar: versusPar)
            }
            if shape.worst.map({ versusPar > $0.versusPar }) ?? true {
                shape.worst = HoleResult(hole: hole, versusPar: versusPar)
            }
        }
        return shape
    }
}
