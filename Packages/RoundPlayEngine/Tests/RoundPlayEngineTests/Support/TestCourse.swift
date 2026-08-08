import Foundation
@testable import RoundPlayEngine

extension Course {
    /// A conventional par-72 layout used across engine tests.
    ///
    /// Stroke indexes follow the usual convention: odds on the front nine, evens on the back,
    /// so a 9-handicap gets a shot on every front-nine hole and none on the back.
    static var testPar72: Course {
        let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4,
                    4, 3, 5, 4, 4, 3, 5, 4, 4]
        let strokeIndexes = [1, 11, 17, 3, 7, 15, 13, 5, 9,
                             2, 16, 12, 4, 8, 18, 14, 6, 10]
        let holes = (0..<18).map {
            Hole(number: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0])
        }
        return Course(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!,
                      name: "Test Par 72",
                      holes: holes)
    }
}
