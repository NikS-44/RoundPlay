import Foundation

/// What a player recorded on a hole.
public enum ScoreEventPayload: Equatable, Sendable, Codable {
    /// Gross strokes taken. The overwhelmingly common case.
    case strokes(Int)
    /// Wolf's per-hole choice. The `playerID` on the event is the Wolf.
    case wolfDeclaration(WolfDeclaration)
    /// Bingo Bango Bongo point. The `playerID` on the event is who earned it.
    case holeEvent(HoleEventKind)
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
/// Scores are never overwritten. A correction appends a new event with a higher `sequence`;
/// the earlier one stays for the audit trail. This is why "who changed my score on 14" is a
/// query rather than a feature, and why offline sync needs no merge logic.
public struct ScoreEvent: Equatable, Sendable, Codable, Identifiable {
    /// Client-generated, stable across retries. Makes a flaky connection's duplicate POST a no-op.
    public let id: UUID
    public let hole: Int
    /// Who the event is *about* — not who typed it.
    public let playerID: UUID
    public let payload: ScoreEventPayload
    /// Who typed it. Drives the audit view; may differ from `playerID` when one person keeps score.
    public let enteredBy: UUID
    /// Authoritative ordering. Assigned by the server in Phase 2; monotonic per-device in Phase 1.
    public let sequence: Int

    public init(
        id: UUID,
        hole: Int,
        playerID: UUID,
        payload: ScoreEventPayload,
        enteredBy: UUID,
        sequence: Int
    ) {
        self.id = id
        self.hole = hole
        self.playerID = playerID
        self.payload = payload
        self.enteredBy = enteredBy
        self.sequence = sequence
    }
}
