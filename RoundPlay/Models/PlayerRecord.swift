import Foundation
import SwiftData

/// Someone you play with — your roster, and the "recurring companions" feature.
///
/// Sorted by `lastPlayedAt` so adding the regular Saturday group to a new round is four taps.
/// `linkedAccountID` is unused in Phase 1 and exists so Phase 2 can bind a roster entry to a real
/// signed-in human without a migration.
@Model
final class PlayerRecord {
    var id: UUID = UUID()
    var name: String = ""
    /// Self-reported. `nil` means they play off scratch or have not told us.
    var handicapIndex: Double?
    var linkedAccountID: UUID?
    var lastPlayedAt: Date?
    var playCount: Int = 0
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, handicapIndex: Double? = nil) {
        self.id = id
        self.name = name
        self.handicapIndex = handicapIndex
    }

    /// Course handicap, rounded to whole strokes.
    ///
    /// The real USGA formula factors slope and course rating, which Phase 1 does not collect.
    /// Using the index directly is the standard casual-play approximation and is what a group
    /// agreeing strokes on the first tee would do anyway.
    var courseHandicap: Int {
        Int((handicapIndex ?? 0).rounded())
    }
}
