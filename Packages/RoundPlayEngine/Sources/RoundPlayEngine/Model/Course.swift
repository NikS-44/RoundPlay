import Foundation

/// One hole on a course.
///
/// `strokeIndex` is the hole's difficulty rank, 1 (hardest) through 18 (easiest). It is printed on
/// every physical scorecard and is what handicap strokes are allocated against — without it,
/// net play is impossible.
public struct Hole: Equatable, Sendable, Codable {
    public let number: Int
    public let par: Int
    public let strokeIndex: Int

    public init(number: Int, par: Int, strokeIndex: Int) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
    }
}

public enum CourseValidationError: Error, Equatable, Sendable {
    case wrongHoleCount
    case duplicateStrokeIndex
    case strokeIndexOutOfRange
    case nonSequentialHoleNumbers
    case implausiblePar
}

/// A golf course: a name and 18 holes with par and stroke index.
///
/// Created by whoever plays it first and shared globally thereafter, so validation is strict —
/// one person's typo would otherwise propagate to every future group at that course.
public struct Course: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let holes: [Hole]

    public init(id: UUID, name: String, holes: [Hole]) {
        self.id = id
        self.name = name
        self.holes = holes
    }

    public func hole(_ number: Int) -> Hole? {
        holes.first { $0.number == number }
    }

    public var totalPar: Int { holes.reduce(0) { $0 + $1.par } }

    /// Front nine is holes 1–9, back nine 10–18.
    public func holes(in segment: RoundSegment) -> [Hole] {
        holes.filter { segment.contains(hole: $0.number) }
    }

    /// Validating factory. Use this for anything user-entered.
    public static func validated(id: UUID, name: String, holes: [Hole]) throws -> Course {
        guard holes.count == 18 else { throw CourseValidationError.wrongHoleCount }
        guard Set(holes.map(\.number)) == Set(1...18) else {
            throw CourseValidationError.nonSequentialHoleNumbers
        }
        let indexes = holes.map(\.strokeIndex)
        guard indexes.allSatisfy({ (1...18).contains($0) }) else {
            throw CourseValidationError.strokeIndexOutOfRange
        }
        guard Set(indexes).count == 18 else { throw CourseValidationError.duplicateStrokeIndex }
        guard holes.allSatisfy({ (3...6).contains($0.par) }) else {
            throw CourseValidationError.implausiblePar
        }
        return Course(id: id, name: name, holes: holes.sorted { $0.number < $1.number })
    }
}

/// Which stretch of the round a bet covers. Nassau needs all three.
public enum RoundSegment: String, Equatable, Sendable, Codable, CaseIterable {
    case front
    case back
    case total

    public func contains(hole: Int) -> Bool {
        switch self {
        case .front: (1...9).contains(hole)
        case .back: (10...18).contains(hole)
        case .total: (1...18).contains(hole)
        }
    }

    public var displayName: String {
        switch self {
        case .front: "Front 9"
        case .back: "Back 9"
        case .total: "Total 18"
        }
    }
}
