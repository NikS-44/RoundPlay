import Testing
import Foundation

/// The engine's whole value rests on being deterministic. A stray `import SwiftUI` or a `Date()`
/// inside a settle function would make a settled round recompute differently later, which is the
/// one failure mode that cannot be recovered from — the money already changed hands.
@Test("Engine sources import nothing but Foundation")
func engineImportsOnlyFoundation() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/RoundPlayEngine")

    let banned = ["SwiftUI", "UIKit", "SwiftData", "Combine", "Network", "CloudKit"]
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" } ?? []

    #expect(files.isEmpty == false, "found no engine sources to check")

    for file in files {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for module in banned {
            #expect(
                contents.contains("import \(module)") == false,
                "\(file.lastPathComponent) imports \(module) — the engine must stay pure"
            )
        }
    }
}

@Test("Engine sources contain no non-deterministic calls")
func engineIsDeterministic() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/RoundPlayEngine")

    let banned = ["Date()", "UUID()", ".random", "arc4random"]
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" } ?? []

    for file in files {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for call in banned {
            #expect(
                contents.contains(call) == false,
                "\(file.lastPathComponent) contains \(call) — settlement must be reproducible"
            )
        }
    }
}
