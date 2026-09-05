import Foundation
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// One line on the solo summary comparing this round to the ones before it.
///
/// Deliberately one line and no screen. Trends, cross-course comparison and a stats section are all
/// out of scope — this exists so finishing a solo round lands somewhere, the way settling up lands
/// a group round.
enum SoloRoundHistory {

    /// `nil` when there is nothing honest to say: a first round here, or a round that stopped short.
    static func line(for round: RoundRecord, course: Course, playerID: UUID, in context: ModelContext) -> String? {
        let holes = round.holeSegment.holeRange
        guard let currentGross = fullRoundGross(round, course: course, playerID: playerID, holes: holes) else {
            return nil
        }

        let courseID = round.courseID
        let descriptor = FetchDescriptor<RoundRecord>(
            predicate: #Predicate { $0.courseID == courseID && $0.completedAt != nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        guard let candidates = try? context.fetch(descriptor) else { return nil }

        // Group rounds count: your gross is your gross, whoever you played it with. The segment has
        // to match, or a front nine would look like a course record against eighteen holes.
        let previous = candidates.filter { other in
            other.id != round.id
                && other.holeSegment == round.holeSegment
                && other.orderedSeats.contains { $0.playerID == playerID }
        }

        let scored = previous.compactMap { other -> (date: Date, gross: Int)? in
            guard let gross = fullRoundGross(other, course: course, playerID: playerID, holes: holes),
                  let completedAt = other.completedAt
            else { return nil }
            return (completedAt, gross)
        }
        guard !scored.isEmpty else { return nil }

        let bestPrevious = scored.map(\.gross).min() ?? currentGross
        if currentGross < bestPrevious {
            return "Your best at \(round.courseName)."
        }

        // `scored` inherits the fetch's newest-first order, so the first entry is the last round played.
        let lastGross = scored[0].gross
        let difference = abs(currentGross - lastGross)
        let comparison: String
        switch currentGross - lastGross {
        case 0: comparison = "Same as last time"
        case ..<0: comparison = "\(difference) better than last time"
        default: comparison = "\(difference) worse than last time"
        }
        return "\(comparison) · best there is \(bestPrevious)."
    }

    /// Total gross, but only for a round that covers its whole segment.
    ///
    /// A round abandoned after four holes has a lower gross than any complete one, and comparing
    /// the two would report every walked-off round as a personal best.
    private static func fullRoundGross(_ round: RoundRecord, course: Course, playerID: UUID, holes: ClosedRange<Int>) -> Int? {
        let state = EngineBridge.roundState(for: round, course: course)
        var total = 0
        for hole in holes {
            guard let gross = state.gross(hole: hole, player: playerID) else { return nil }
            total += gross
        }
        return total
    }
}
