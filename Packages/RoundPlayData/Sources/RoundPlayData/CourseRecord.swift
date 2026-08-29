import Foundation
import SwiftData
import RoundPlayEngine

@Model
public final class CourseRecord {
    public var id: UUID = UUID()
    public var name: String = ""
    public var pars: [Int] = []
    public var strokeIndexes: [Int] = []
    public var createdAt: Date = Date()
    public var lastPlayedAt: Date?
    public var openGolfID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        pars: [Int],
        strokeIndexes: [Int],
        openGolfID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.pars = pars
        self.strokeIndexes = strokeIndexes
        self.openGolfID = openGolfID
    }

    public var engineCourse: Course? {
        guard pars.count == 18, strokeIndexes.count == 18 else { return nil }
        let holes = (0..<18).map {
            Hole(number: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0])
        }
        return try? Course.validated(id: id, name: name, holes: holes)
    }

    public var totalPar: Int { pars.reduce(0, +) }
}
