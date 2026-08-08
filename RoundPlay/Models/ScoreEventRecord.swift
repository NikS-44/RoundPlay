import Foundation
import SwiftData
import RoundPlayEngine

/// One append-only entry in a round's log.
///
/// **Never update or delete one of these.** A correction appends a new record with a higher
/// `sequence`; the earlier one is what makes the audit view possible and what Phase 2's offline
/// sync replays. Mutating in place would destroy both.
@Model
final class ScoreEventRecord {
    var id: UUID = UUID()
    var hole: Int = 0
    var playerID: UUID = UUID()
    /// `ScoreEventPayload` encoded as JSON — the payload is an enum with associated values.
    var payloadData: Data = Data()
    var enteredBy: UUID = UUID()
    var enteredByName: String = ""
    var sequence: Int = 0
    var recordedAt: Date = Date()

    init(
        id: UUID = UUID(),
        hole: Int,
        playerID: UUID,
        payload: ScoreEventPayload,
        enteredBy: UUID,
        enteredByName: String,
        sequence: Int
    ) throws {
        self.id = id
        self.hole = hole
        self.playerID = playerID
        self.payloadData = try JSONEncoder().encode(payload)
        self.enteredBy = enteredBy
        self.enteredByName = enteredByName
        self.sequence = sequence
    }

    var payload: ScoreEventPayload? {
        try? JSONDecoder().decode(ScoreEventPayload.self, from: payloadData)
    }

    var engineEvent: ScoreEvent? {
        guard let payload else { return nil }
        return ScoreEvent(
            id: id, hole: hole, playerID: playerID,
            payload: payload, enteredBy: enteredBy, sequence: sequence
        )
    }
}
