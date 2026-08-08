import Foundation
import SwiftData
import RoundPlayEngine

/// A course as entered by whoever played it first.
///
/// Pars and stroke indexes are stored as flat 18-element arrays rather than a child model: they
/// are always read together, never queried individually, and a relationship would buy nothing.
@Model
final class CourseRecord {
    var id: UUID = UUID()
    var name: String = ""
    var pars: [Int] = []
    var strokeIndexes: [Int] = []
    var createdAt: Date = Date()
    var lastPlayedAt: Date?

    init(id: UUID = UUID(), name: String, pars: [Int], strokeIndexes: [Int]) {
        self.id = id
        self.name = name
        self.pars = pars
        self.strokeIndexes = strokeIndexes
    }

    /// Engine value type. Returns `nil` when the record is incomplete or invalid — callers must
    /// treat that as "this course cannot be played" rather than substituting defaults.
    var engineCourse: Course? {
        guard pars.count == 18, strokeIndexes.count == 18 else { return nil }
        let holes = (0..<18).map {
            Hole(number: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0])
        }
        return try? Course.validated(id: id, name: name, holes: holes)
    }

    var totalPar: Int { pars.reduce(0, +) }
}
