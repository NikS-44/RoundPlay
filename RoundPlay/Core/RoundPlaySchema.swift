import Foundation
import SwiftData
import os

private let schemaLogger = Logger(subsystem: "app.roundplay", category: "Schema")

/// SwiftData container setup.
///
/// Phase 1 is local-only: no CloudKit, no sync. Phase 2 makes the server authoritative and
/// demotes this store to a cache plus an outbox, so there is deliberately no migration plan or
/// versioned store filename here — that work would be thrown away.
enum RoundPlaySchema {
    static var allModelTypes: [any PersistentModel.Type] {
        [
            PlayerRecord.self,
            CourseRecord.self,
            FavoriteCourseRecord.self,
            RoundRecord.self,
            SeatRecord.self,
            GameInstanceRecord.self,
            ScoreEventRecord.self
        ]
    }

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(allModelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            schemaLogger.error("Failed to create ModelContainer: \(error.localizedDescription)")
            // An in-memory fallback keeps the app usable rather than crashing on launch.
            // Phase 2 replaces this with a real recovery path once the server holds the truth.
            return try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
    }

    static let appContainer: ModelContainer = makeContainer()
}
