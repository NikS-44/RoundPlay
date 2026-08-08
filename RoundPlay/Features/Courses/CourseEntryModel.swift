import Foundation
import Observation
import RoundPlayEngine

/// Editing state for a course being entered.
///
/// Pre-filled with a conventional par-72 layout and the standard odd-front/even-back stroke index
/// pattern, because most courses are close to it — the user is correcting a few holes rather than
/// entering 36 numbers from scratch.
@Observable
final class CourseEntryModel {
    var name: String = ""
    var pars: [Int]
    var strokeIndexes: [Int]

    init() {
        pars = [4, 5, 3, 4, 4, 3, 5, 4, 4,
                4, 3, 5, 4, 4, 3, 5, 4, 4]
        strokeIndexes = [1, 11, 17, 3, 7, 15, 13, 5, 9,
                         2, 16, 12, 4, 8, 18, 14, 6, 10]
    }

    var totalPar: Int { pars.reduce(0, +) }

    /// Human-readable reason the course cannot be saved, or `nil` when it is valid.
    ///
    /// Duplicate stroke indexes are the error users actually make — transposing two holes while
    /// copying — so it names the offending number rather than saying "invalid".
    var validationMessage: String? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Give the course a name."
        }
        let counts = Dictionary(grouping: strokeIndexes, by: { $0 }).mapValues(\.count)
        if let duplicate = counts.first(where: { $0.value > 1 })?.key {
            return "Stroke index \(duplicate) is used more than once. Each hole needs its own 1–18."
        }
        if Set(strokeIndexes) != Set(1...18) {
            let missing = Set(1...18).subtracting(strokeIndexes).sorted()
            return "Missing stroke index \(missing.map(String.init).joined(separator: ", "))."
        }
        return nil
    }

    var isValid: Bool { validationMessage == nil }
}
