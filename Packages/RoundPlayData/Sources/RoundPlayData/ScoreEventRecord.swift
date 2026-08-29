import Foundation
import SwiftData
import RoundPlayEngine

@Model
public final class ScoreEventRecord {
    public var id: UUID = UUID()
    public var hole: Int = 0
    public var playerID: UUID = UUID()
    public var payloadData: Data = Data()
    public var enteredBy: UUID = UUID()
    public var enteredByName: String = ""
    public var sequence: Int = 0
    public var recordedAt: Date = Date()
    /// Physical device that produced this event. Attribution only — not part of fold order.
    public var deviceID: UUID = UUID()

    public init(
        id: UUID = UUID(),
        hole: Int,
        playerID: UUID,
        payload: ScoreEventPayload,
        enteredBy: UUID,
        enteredByName: String,
        sequence: Int,
        recordedAt: Date = Date(),
        deviceID: UUID = DeviceIdentity.id
    ) throws {
        self.id = id
        self.hole = hole
        self.playerID = playerID
        self.payloadData = try JSONEncoder().encode(payload)
        self.enteredBy = enteredBy
        self.enteredByName = enteredByName
        self.sequence = sequence
        self.recordedAt = recordedAt
        self.deviceID = deviceID
    }

    public var payload: ScoreEventPayload? {
        try? JSONDecoder().decode(ScoreEventPayload.self, from: payloadData)
    }

    public var engineEvent: ScoreEvent? {
        guard let payload else { return nil }
        return ScoreEvent(
            id: id, hole: hole, playerID: playerID,
            payload: payload, enteredBy: enteredBy, sequence: sequence,
            recordedAt: recordedAt
        )
    }

    public static func auditSorted(_ events: [ScoreEventRecord]) -> [ScoreEventRecord] {
        events.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt > $1.recordedAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }
}
