import Testing
import Foundation
@testable import RoundPlayEngine

private let modelA = UUID(uuidString: "80000000-0000-0000-0000-000000000001")!
private let modelB = UUID(uuidString: "80000000-0000-0000-0000-000000000002")!

@Test("Round segments include only their physical holes")
func roundSegments() {
    #expect(RoundSegment.front.contains(hole: 1))
    #expect(RoundSegment.front.contains(hole: 9))
    #expect(!RoundSegment.front.contains(hole: 10))
    #expect(RoundSegment.back.contains(hole: 10))
    #expect(RoundSegment.back.contains(hole: 18))
    #expect(!RoundSegment.back.contains(hole: 9))
    #expect(RoundSegment.total.contains(hole: 18))
    #expect(RoundSegment.front.displayName == "Front 9")
}

@Test("Course validation reports each malformed input")
func courseValidationFailures() {
    let valid = (1...18).map { Hole(number: $0, par: 4, strokeIndex: $0) }
    #expect(throws: CourseValidationError.nonSequentialHoleNumbers) {
        try Course.validated(id: UUID(), name: "Bad", holes: valid.dropLast() + [Hole(number: 19, par: 4, strokeIndex: 18)])
    }
    #expect(throws: CourseValidationError.strokeIndexOutOfRange) {
        try Course.validated(id: UUID(), name: "Bad", holes: valid.dropLast() + [Hole(number: 18, par: 4, strokeIndex: 19)])
    }
    #expect(throws: CourseValidationError.implausiblePar) {
        try Course.validated(id: UUID(), name: "Bad", holes: valid.dropLast() + [Hole(number: 18, par: 2, strokeIndex: 18)])
    }
    let shuffled = valid.reversed()
    let course = try? Course.validated(id: UUID(), name: "Good", holes: Array(shuffled))
    #expect(course?.holes.map(\.number) == Array(1...18))
}

@Test("Score event payloads and configurations round-trip through Codable")
func codableRoundTrips() throws {
    let payloads: [ScoreEventPayload] = [.strokes(7), .wolfDeclaration(.partner(modelB)), .wolfDeclaration(.lone), .holeEvent(.bango), .clearStrokes, .clearHoleEvent(.bingo)]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for payload in payloads {
        #expect(try decoder.decode(ScoreEventPayload.self, from: encoder.encode(payload)) == payload)
    }

    let configs: [GameConfiguration] = [
        .strokePlay(StrokePlayConfig()),
        .matchPlay(MatchPlayConfig(unitStake: 2)),
        .bestBall(BestBallConfig(unitStake: 2)),
        .skins(SkinsConfig(unitStake: 2.5)),
        .nassau(NassauConfig(unitStake: 3, pressAt: nil)),
        .stableford(.modified),
        .nines(NinesConfig(unitStake: 1)),
        .wolf(.standard(unitStake: 4)),
        .bingoBangoBongo(BingoBangoBongoConfig(unitStake: 1))
    ]
    for configuration in configs {
        #expect(try decoder.decode(GameConfiguration.self, from: encoder.encode(configuration)) == configuration)
        #expect(configuration.unitStake == configuration.unitStake)
    }
}

@Test("RoundState uses deterministic UUID ordering when sequence numbers tie")
func equalSequenceIsDeterministic() {
    let lowID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
    let highID = UUID(uuidString: "81000000-0000-0000-0000-000000000002")!
    let seats = [Seat(playerID: modelA, name: "A", courseHandicap: 0), Seat(playerID: modelB, name: "B", courseHandicap: 0)]
    let events = [
        ScoreEvent(id: highID, hole: 1, playerID: modelA, payload: .strokes(6), enteredBy: modelA, sequence: 1),
        ScoreEvent(id: lowID, hole: 1, playerID: modelA, payload: .strokes(5), enteredBy: modelA, sequence: 1)
    ]
    #expect(RoundState(log: events, seats: seats, course: .testPar72).gross(hole: 1, player: modelA) == 6)
}

@Test("Wolf tail stop rule ignores holes 17 and 18")
func wolfTailRule() {
    let seats = (1...3).map { Seat(playerID: UUID(uuidString: "82000000-0000-0000-0000-00000000000\($0)")!, name: "P\($0)", courseHandicap: 0) }
    var events: [ScoreEvent] = []
    var sequence = 0
    for hole in [16, 17, 18] {
        sequence += 1
        events.append(ScoreEvent(id: UUID(), hole: hole, playerID: seats[0].playerID, payload: .wolfDeclaration(.lone), enteredBy: seats[0].playerID, sequence: sequence))
        for seat in seats {
            sequence += 1
            events.append(ScoreEvent(id: UUID(), hole: hole, playerID: seat.playerID, payload: .strokes(seat == seats[0] ? 3 : 5), enteredBy: seats[0].playerID, sequence: sequence))
        }
    }
    let state = RoundState(log: events, seats: seats, course: .testPar72)
    let result = WolfEngine.settle(state: state, config: WolfConfig(unitStake: 1, partnerWinPoints: 1, fieldWinPoints: 1, loneWolfWinPoints: 4, loneWolfLossPoints: 1, tailHoleRule: .stopAfter16))
    #expect(result.points(for: seats[0].playerID) == 4)
    #expect(result.holeExplanations.map(\.hole) == [16])
}
