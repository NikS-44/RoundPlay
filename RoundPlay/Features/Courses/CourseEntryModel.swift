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

    /// Pre-fills from a catalog course. Pars are simple overrides — any hole missing a real value
    /// keeps the conventional default. Stroke indexes are not: only ~0.14% of the catalog has a
    /// complete 18-hole scorecard, so naively overlaying a handful of real values onto the fixed
    /// default permutation collides almost every time (two holes both claiming "SI 7", say).
    /// Instead, known real values are placed first, then whatever indexes they *don't* use get
    /// handed to the remaining holes in order — the result is always a clean 1–18 permutation,
    /// with every known real value honored exactly and the gaps merely unconfirmed rather than
    /// wrong.
    convenience init(prefilledFrom course: OpenGolfCourse) {
        self.init()
        name = course.name
        for (index, par) in course.holePars.enumerated() where index < pars.count {
            // Same defensiveness as the stroke indexes below: an out-of-range source value is
            // treated as unknown rather than trusted, since nothing downstream re-validates par.
            if let par, (3...6).contains(par) { pars[index] = par }
        }

        var resolved = [Int?](repeating: nil, count: 18)
        var usedIndexes = Set<Int>()
        for (index, handicap) in course.holeHandicaps.enumerated() where index < 18 {
            // A malformed source value (out of range, or a duplicate within the source itself)
            // is treated as unknown rather than trusted verbatim.
            if let handicap, (1...18).contains(handicap), !usedIndexes.contains(handicap) {
                resolved[index] = handicap
                usedIndexes.insert(handicap)
            }
        }
        var remainingIndexes = (1...18).filter { !usedIndexes.contains($0) }.makeIterator()
        for hole in 0..<18 where resolved[hole] == nil {
            resolved[hole] = remainingIndexes.next()
        }
        strokeIndexes = resolved.map { $0 ?? 1 }
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
