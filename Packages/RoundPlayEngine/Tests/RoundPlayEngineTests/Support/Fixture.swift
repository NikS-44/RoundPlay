import Foundation
import Testing
@testable import RoundPlayEngine

/// A recorded round and the money it must settle to.
///
/// Language-neutral on purpose: the Phase 4 TypeScript engine loads these same files and must
/// produce the same `expectedMoney` to the cent.
struct EngineFixture: Codable {
    struct ExpectedStanding: Codable {
        let playerName: String
        let points: Int
        /// String-encoded to survive JSON without float rounding.
        let money: String
    }

    let name: String
    let engineVersion: String
    let course: Course
    let seats: [Seat]
    let log: [ScoreEvent]
    let configuration: GameConfiguration
    let expected: [ExpectedStanding]

    static func loadAll() throws -> [EngineFixture] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures") ?? []
        let decoder = JSONDecoder()
        return try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try decoder.decode(EngineFixture.self, from: Data(contentsOf: $0)) }
    }
}
