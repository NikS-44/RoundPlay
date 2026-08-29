import Foundation

/// What a player recorded on a hole.
public enum ScoreEventPayload: Equatable, Sendable, Codable {
    /// Gross strokes taken. The overwhelmingly common case.
    case strokes(Int)
    /// Wolf's per-hole choice. The `playerID` on the event is the Wolf.
    case wolfDeclaration(WolfDeclaration)
    /// Bingo Bango Bongo point. The `playerID` on the event is who earned it.
    case holeEvent(HoleEventKind)
    /// The group's answer to a press they were offered. The `playerID` on the event is the side
    /// that was down and had the call; the `hole` is the hole the press would start on.
    case press(PressDecision)
    /// Removes the current gross score for this hole/player. The event remains in the audit log.
    case clearStrokes
    /// Removes the current winner for a hole-event kind. The event remains in the audit log.
    case clearHoleEvent(HoleEventKind)
}

/// Whether a side took the press it was offered.
///
/// A press is real money on a bet nobody agreed to at the first tee, so it is recorded as a
/// decision rather than inferred. Declining is recorded too: it is what stops the same offer
/// coming back on the next hole, and it is the answer a group will want to see in the log when
/// the bet is settled in the parking lot.
public enum PressDecision: String, Equatable, Sendable, Codable {
    case accepted
    case declined
}

/// The Wolf's decision for a hole: take a partner, or play the field alone.
public enum WolfDeclaration: Equatable, Sendable, Codable {
    case partner(UUID)
    case lone
}

/// The three Bingo Bango Bongo points.
public enum HoleEventKind: String, Equatable, Sendable, Codable, CaseIterable {
    /// First ball on the green.
    case bingo
    /// Closest to the pin once every ball is on the green.
    case bango
    /// First in the hole.
    case bongo
}

/// One append-only entry in a round's log.
///
/// Scores are never overwritten. A correction appends a new event; the earlier one stays for
/// the audit trail. Across devices, "current value" is the latest `recordedAt` (then `id`).
public struct ScoreEvent: Equatable, Sendable, Codable, Identifiable {
    /// Client-generated, stable across retries. Makes a flaky connection's duplicate POST a no-op.
    public let id: UUID
    public let hole: Int
    /// Who the event is *about* — not who typed it.
    public let playerID: UUID
    public let payload: ScoreEventPayload
    /// Who typed it. Drives the audit view; may differ from `playerID` when one person keeps score.
    public let enteredBy: UUID
    /// Per-device local counter. Kept for compatibility; fold order uses `recordedAt`.
    public let sequence: Int
    /// Wall clock when the event was entered. Comparable across paired devices.
    public let recordedAt: Date

    public init(
        id: UUID,
        hole: Int,
        playerID: UUID,
        payload: ScoreEventPayload,
        enteredBy: UUID,
        sequence: Int,
        recordedAt: Date? = nil
    ) {
        self.id = id
        self.hole = hole
        self.playerID = playerID
        self.payload = payload
        self.enteredBy = enteredBy
        self.sequence = sequence
        // Tests that omit `recordedAt` keep working: sequence maps onto a comparable instant.
        self.recordedAt = recordedAt ?? Date(timeIntervalSince1970: TimeInterval(sequence))
    }

    /// Ascending fold order: later `recordedAt` wins; `id` breaks exact ties.
    public static func foldAscending(_ lhs: ScoreEvent, _ rhs: ScoreEvent) -> Bool {
        if lhs.recordedAt != rhs.recordedAt {
            return lhs.recordedAt < rhs.recordedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private enum CodingKeys: String, CodingKey {
        case id, hole, playerID, payload, enteredBy, sequence, recordedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hole = try container.decode(Int.self, forKey: .hole)
        playerID = try container.decode(UUID.self, forKey: .playerID)
        payload = try container.decode(ScoreEventPayload.self, forKey: .payload)
        enteredBy = try container.decode(UUID.self, forKey: .enteredBy)
        sequence = try container.decode(Int.self, forKey: .sequence)
        recordedAt = try container.decodeIfPresent(Date.self, forKey: .recordedAt)
            ?? Date(timeIntervalSince1970: TimeInterval(sequence))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hole, forKey: .hole)
        try container.encode(playerID, forKey: .playerID)
        try container.encode(payload, forKey: .payload)
        try container.encode(enteredBy, forKey: .enteredBy)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(recordedAt, forKey: .recordedAt)
    }
}
