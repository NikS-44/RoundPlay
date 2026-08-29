import Foundation
import Testing
import SwiftData
import RoundPlayEngine
@testable import RoundPlayData

private func context() -> ModelContext {
    ModelContext(RoundPlaySchema.makeContainer(inMemory: true))
}

private func sampleRound(id: UUID = UUID(), extraEvent: ScoreEventRecord? = nil) throws -> RoundRecord {
    let round = RoundRecord(id: id, courseID: UUID(), courseName: "Links")
    let seat = SeatRecord(playerID: UUID(), name: "Ann", courseHandicap: 0, position: 0)
    round.seats = [seat]
    let game = try GameInstanceRecord(configuration: .skins(SkinsConfig(unitStake: 2)))
    round.games = [game]
    if let extraEvent {
        round.events = [extraEvent]
    }
    return round
}

@Test("Merge overlapping round snapshots unions events without duplicates")
func mergeOverlappingEvents() throws {
    let ctx = context()
    let roundID = UUID()
    let sharedID = UUID()
    let shared = try ScoreEventRecord(
        id: sharedID, hole: 1, playerID: UUID(), payload: .strokes(4),
        enteredBy: UUID(), enteredByName: "Ann", sequence: 1,
        recordedAt: Date(timeIntervalSince1970: 10)
    )
    let localOnly = try ScoreEventRecord(
        id: UUID(), hole: 2, playerID: UUID(), payload: .strokes(5),
        enteredBy: UUID(), enteredByName: "Ann", sequence: 2,
        recordedAt: Date(timeIntervalSince1970: 20)
    )
    let local = try sampleRound(id: roundID, extraEvent: shared)
    local.events = (local.events ?? []) + [localOnly]
    ctx.insert(local)
    try ctx.save()

    let remoteEvent = try ScoreEventRecord(
        id: UUID(), hole: 3, playerID: UUID(), payload: .strokes(3),
        enteredBy: UUID(), enteredByName: "Watch", sequence: 1,
        recordedAt: Date(timeIntervalSince1970: 30)
    )
    let remoteRound = try sampleRound(id: roundID, extraEvent: shared)
    remoteRound.events = (remoteRound.events ?? []) + [remoteEvent]
    let payload = RoundsPayload(rounds: [RoundSnapshot(record: remoteRound)])

    try SyncMerger.mergeRounds(payload, into: ctx)
    try SyncMerger.mergeRounds(payload, into: ctx)

    let merged = try ctx.fetch(FetchDescriptor<RoundRecord>()).first
    let ids = Set((merged?.events ?? []).map(\.id))
    #expect(ids.count == 3)
    #expect(ids.contains(sharedID))
}

@Test("Merge brings in a seat the other side does not have")
func mergeMissingSeat() throws {
    let ctx = context()
    let roundID = UUID()
    let local = try sampleRound(id: roundID)
    ctx.insert(local)
    try ctx.save()

    let extra = SeatRecord(playerID: UUID(), name: "Ben", courseHandicap: 8, position: 1)
    let remote = RoundSnapshot(record: local)
    var snapshot = remote
    snapshot.seats.append(SeatSnapshot(record: extra))
    try SyncMerger.mergeRounds(RoundsPayload(rounds: [snapshot]), into: ctx)

    let merged = try ctx.fetch(FetchDescriptor<RoundRecord>()).first
    #expect((merged?.seats ?? []).count == 2)
    #expect((merged?.seats ?? []).contains { $0.name == "Ben" })
}

@Test("Repeated merge of the same payload is idempotent")
func mergeIsIdempotent() throws {
    let ctx = context()
    let round = try sampleRound()
    let payload = RoundsPayload(rounds: [RoundSnapshot(record: round)])
    try SyncMerger.mergeRounds(payload, into: ctx)
    try SyncMerger.mergeRounds(payload, into: ctx)
    try SyncMerger.mergeRounds(payload, into: ctx)
    #expect(try ctx.fetch(FetchDescriptor<RoundRecord>()).count == 1)
    #expect(try ctx.fetch(FetchDescriptor<SeatRecord>()).count == 1)
    #expect(try ctx.fetch(FetchDescriptor<GameInstanceRecord>()).count == 1)
}

@Test("Audit log orders newest recordedAt first")
func auditLogOrdering() throws {
    let older = try ScoreEventRecord(
        hole: 1, playerID: UUID(), payload: .strokes(5),
        enteredBy: UUID(), enteredByName: "A", sequence: 9,
        recordedAt: Date(timeIntervalSince1970: 1)
    )
    let newer = try ScoreEventRecord(
        hole: 1, playerID: UUID(), payload: .strokes(4),
        enteredBy: UUID(), enteredByName: "B", sequence: 1,
        recordedAt: Date(timeIntervalSince1970: 99)
    )
    #expect(ScoreEventRecord.auditSorted([older, newer]).first?.sequence == 1)
}

@Test("Hole entry sequence inserts wolf and BBB around scores")
func holeEntrySequence() {
    let steps = HoleEntrySequence.steps(
        requiredInputs: [.partnerChoice, .strokes, .holeEvents],
        seatCount: 2
    )
    #expect(steps == [.partnerChoice, .score(seatIndex: 0), .score(seatIndex: 1), .holeEvents])
}

@Test("Previous-round match is order-independent on player ids")
func previousRoundMatch() throws {
    let a = UUID()
    let b = UUID()
    let round = RoundRecord(courseID: UUID(), courseName: "X")
    round.seats = [
        SeatRecord(playerID: b, name: "B", courseHandicap: 0, position: 0),
        SeatRecord(playerID: a, name: "A", courseHandicap: 0, position: 1)
    ]
    #expect(PreviousRoundMatch.find(playerIDs: [a, b], in: [round])?.id == round.id)
    #expect(PreviousRoundMatch.find(playerIDs: [a], in: [round]) == nil)
}
