import Foundation
import SwiftData
import os

private let schemaLogger = Logger(subsystem: "app.roundplay", category: "Schema")

public enum RoundPlaySchema {
    public static var allModelTypes: [any PersistentModel.Type] {
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

    public static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(allModelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            schemaLogger.error("Failed to create ModelContainer: \(error.localizedDescription)")
            return try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
    }

    public static let appContainer: ModelContainer = makeContainer()
}
