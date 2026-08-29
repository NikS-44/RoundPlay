import Foundation
import SwiftData
import RoundPlayEngine

/// The only seam between SwiftData and the scoring engine.
public enum EngineBridge {

    public enum BridgeError: Error {
        case courseUnavailable
        case invalidEvent
    }

    /// Optional hook fired after a local write so each platform can push a sync payload.
    nonisolated(unsafe) public static var onLocalChange: (() -> Void)?

    public static func roundState(for round: RoundRecord, course: Course) -> RoundState {
        RoundState(
            log: (round.events ?? []).compactMap(\.engineEvent),
            seats: round.orderedSeats.map(\.engineSeat),
            course: course,
            segment: round.holeSegment,
            handicapSettings: round.handicapSettings
        )
    }

    public static func settlements(for round: RoundRecord, course: Course) -> [Settlement] {
        let state = roundState(for: round, course: course)
        return (round.games ?? []).compactMap { game in
            guard let configuration = game.configuration else { return nil }
            return try? GameLibrary.settle(configuration, state: state)
        }
    }

    public static func nassauPressOffer(for round: RoundRecord, course: Course) -> NassauEngine.PressOffer? {
        let config = (round.games ?? []).compactMap { game -> NassauConfig? in
            guard case .nassau(let config) = game.configuration else { return nil }
            return config
        }.first
        guard let config else { return nil }
        return NassauEngine.pressOffer(state: roundState(for: round, course: course), config: config)
    }

    @discardableResult
    public static func append(
        payload: ScoreEventPayload,
        hole: Int,
        playerID: UUID,
        to round: RoundRecord,
        enteredBy: UUID,
        enteredByName: String,
        in context: ModelContext
    ) throws -> ScoreEventRecord {
        let record = try ScoreEventRecord(
            hole: hole,
            playerID: playerID,
            payload: payload,
            enteredBy: enteredBy,
            enteredByName: enteredByName,
            sequence: round.nextSequence
        )
        round.nextSequence += 1
        round.events = (round.events ?? []) + [record]
        context.insert(record)
        try context.save()
        onLocalChange?()
        return record
    }

    public static func appendStrokes(
        _ strokes: Int, hole: Int, playerID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .strokes(strokes), hole: hole, playerID: playerID,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    public static func clearStrokes(
        hole: Int, playerID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .clearStrokes, hole: hole, playerID: playerID,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    public static func clearHoleEvent(
        _ kind: HoleEventKind, hole: Int, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .clearHoleEvent(kind), hole: hole, playerID: enteredBy,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    public static func appendWolfDeclaration(
        _ declaration: WolfDeclaration, hole: Int, wolfID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .wolfDeclaration(declaration), hole: hole, playerID: wolfID,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    public static func appendPress(
        _ decision: PressDecision, hole: Int, playerID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .press(decision), hole: hole, playerID: playerID,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    public static func appendHoleEvent(
        _ kind: HoleEventKind, hole: Int, playerID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .holeEvent(kind), hole: hole, playerID: playerID,
                   to: round, enteredBy: enteredBy,
                   enteredByName: enteredByName, in: context)
    }
}
