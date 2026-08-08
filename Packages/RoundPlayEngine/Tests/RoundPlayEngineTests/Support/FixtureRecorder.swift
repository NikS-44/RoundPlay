import Foundation
import Testing
@testable import RoundPlayEngine

/// Run with `swift test --filter recordFixtures` to (re)write the JSON fixtures on disk.
///
/// Disabled by default: it writes into the source tree, which a normal test run must not do.
/// Enable deliberately when a rule legitimately changes, then review the JSON diff before committing —
/// that diff *is* the record of what money moved.
@Test(.disabled("Run manually to re-record fixtures"))
func recordFixtures() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // Support/
        .deletingLastPathComponent()          // RoundPlayEngineTests/
        .appendingPathComponent("Fixtures")

    for fixture in FixtureCatalog.all {
        let data = try encoder.encode(fixture)
        try data.write(to: directory.appendingPathComponent("\(fixture.name).json"))
    }
}
