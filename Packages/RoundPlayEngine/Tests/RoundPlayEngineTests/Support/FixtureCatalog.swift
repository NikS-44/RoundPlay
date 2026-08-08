import Foundation
@testable import RoundPlayEngine

/// The canonical fixtures. Add one for every rule that has ever been argued about.
enum FixtureCatalog {
    static let ann = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    static let ben = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
    static let cal = UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!
    static let dee = UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!

    static var all: [EngineFixture] { [skinsCarryover, ninesTies, wolfLoneWin] }

    private static func threeSeats() -> [Seat] {
        [
            Seat(playerID: ann, name: "Ann", courseHandicap: 0),
            Seat(playerID: ben, name: "Ben", courseHandicap: 0),
            Seat(playerID: cal, name: "Cal", courseHandicap: 0)
        ]
    }

    private static func strokes(
        _ entries: [(hole: Int, player: UUID, strokes: Int)]
    ) -> [ScoreEvent] {
        entries.enumerated().map { index, entry in
            ScoreEvent(
                id: UUID(uuidString: String(format: "B0000000-0000-0000-0000-%012d", index))!,
                hole: entry.hole, playerID: entry.player,
                payload: .strokes(entry.strokes), enteredBy: ann, sequence: index + 1
            )
        }
    }

    /// Hole 1 ties and carries; Ann wins two skins on hole 2 at $5 a skin from two opponents.
    static var skinsCarryover: EngineFixture {
        EngineFixture(
            name: "skins-carryover",
            engineVersion: RoundPlayEngineVersion.current,
            course: .testPar72,
            seats: threeSeats(),
            log: strokes([
                (1, ann, 4), (1, ben, 4), (1, cal, 5),
                (2, ann, 3), (2, ben, 5), (2, cal, 5)
            ]),
            configuration: .skins(SkinsConfig(unitStake: 5)),
            expected: [
                .init(playerName: "Ann", points: 2, money: "20"),
                .init(playerName: "Ben", points: 0, money: "-10"),
                .init(playerName: "Cal", points: 0, money: "-10")
            ]
        )
    }

    /// Every Nines tie shape in one round: clean, all-tied, tied-low, tied-high.
    static var ninesTies: EngineFixture {
        EngineFixture(
            name: "nines-ties",
            engineVersion: RoundPlayEngineVersion.current,
            course: .testPar72,
            seats: threeSeats(),
            log: strokes([
                (1, ann, 3), (1, ben, 4), (1, cal, 5),   // 5 / 3 / 1
                (2, ann, 4), (2, ben, 4), (2, cal, 4),   // 3 / 3 / 3
                (3, ann, 3), (3, ben, 3), (3, cal, 5),   // 4 / 4 / 1
                (4, ann, 3), (4, ben, 5), (4, cal, 5)    // 5 / 2 / 2
            ]),
            configuration: .nines(NinesConfig(unitStake: 1)),
            expected: [
                // Ann 17, Ben 12, Cal 7 → differences at $1: Ann +15, Ben 0, Cal −15.
                .init(playerName: "Ann", points: 17, money: "15"),
                .init(playerName: "Ben", points: 12, money: "0"),
                .init(playerName: "Cal", points: 7, money: "-15")
            ]
        )
    }

    /// A Lone Wolf that comes off — the biggest single-hole swing in the library.
    static var wolfLoneWin: EngineFixture {
        let seats = [
            Seat(playerID: ann, name: "Ann", courseHandicap: 0),
            Seat(playerID: ben, name: "Ben", courseHandicap: 0),
            Seat(playerID: cal, name: "Cal", courseHandicap: 0),
            Seat(playerID: dee, name: "Dee", courseHandicap: 0)
        ]
        var log = strokes([(1, ann, 3), (1, ben, 4), (1, cal, 4), (1, dee, 4)])
        log.insert(
            ScoreEvent(
                id: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
                hole: 1, playerID: ann, payload: .wolfDeclaration(.lone),
                enteredBy: ann, sequence: 0
            ),
            at: 0
        )
        return EngineFixture(
            name: "wolf-lone-win",
            engineVersion: RoundPlayEngineVersion.current,
            course: .testPar72,
            seats: seats,
            log: log,
            configuration: .wolf(.standard(unitStake: 1)),
            expected: [
                // Ann 4 pts, everyone else 0 → Ann +12, each opponent −4.
                .init(playerName: "Ann", points: 4, money: "12"),
                .init(playerName: "Ben", points: 0, money: "-4"),
                .init(playerName: "Cal", points: 0, money: "-4"),
                .init(playerName: "Dee", points: 0, money: "-4")
            ]
        )
    }
}
