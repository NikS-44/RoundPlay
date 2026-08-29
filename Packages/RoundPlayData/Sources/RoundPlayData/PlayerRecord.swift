import Foundation
import SwiftData

/// Someone you play with — your roster, and the "recurring companions" feature.
@Model
public final class PlayerRecord {
    public var id: UUID = UUID()
    public var name: String = ""
    public var handicapIndex: Double?
    public var linkedAccountID: UUID?
    public var lastPlayedAt: Date?
    public var playCount: Int = 0
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), name: String, handicapIndex: Double? = nil) {
        self.id = id
        self.name = name
        self.handicapIndex = handicapIndex
    }

    public var courseHandicap: Int {
        Int((handicapIndex ?? 0).rounded())
    }
}
