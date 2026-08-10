import Foundation
import SwiftData
import RoundPlayEngine

/// The only seam between SwiftData and the scoring engine.
///
/// Views call this and never assemble `RoundState` themselves, so the record→value-type mapping
/// is defined exactly once.
enum EngineBridge {

    enum BridgeError: Error {
        case courseUnavailable
        case invalidEvent
    }

    static func roundState(for round: RoundRecord, course: Course) -> RoundState {
        RoundState(
            log: (round.events ?? []).compactMap(\.engineEvent),
            seats: round.orderedSeats.map(\.engineSeat),
            course: course,
            segment: round.holeSegment,
            handicapSettings: round.handicapSettings
        )
    }

    /// Settles every game in the round. A game whose configuration fails to decode, or whose
    /// player count no longer fits, is skipped rather than crashing the dashboard.
    static func settlements(for round: RoundRecord, course: Course) -> [Settlement] {
        let state = roundState(for: round, course: course)
        return (round.games ?? []).compactMap { game in
            guard let configuration = game.configuration else { return nil }
            return try? GameLibrary.settle(configuration, state: state)
        }
    }

    // MARK: - Appending events

    @discardableResult
    static func append(
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
        return record
    }

    static func appendStrokes(
        _ strokes: Int, hole: Int, playerID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .strokes(strokes), hole: hole, playerID: playerID,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    static func clearStrokes(
        hole: Int, playerID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .clearStrokes, hole: hole, playerID: playerID,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    static func clearHoleEvent(
        _ kind: HoleEventKind, hole: Int, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .clearHoleEvent(kind), hole: hole, playerID: enteredBy,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    static func appendWolfDeclaration(
        _ declaration: WolfDeclaration, hole: Int, wolfID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .wolfDeclaration(declaration), hole: hole, playerID: wolfID,
                   to: round, enteredBy: enteredBy, enteredByName: enteredByName, in: context)
    }

    static func appendHoleEvent(
        _ kind: HoleEventKind, hole: Int, playerID: UUID, to round: RoundRecord,
        enteredBy: UUID, enteredByName: String, in context: ModelContext
    ) throws {
        try append(payload: .holeEvent(kind), hole: hole, playerID: playerID,
                   to: round, enteredBy: enteredBy,
                   enteredByName: enteredByName, in: context)
    }
}
