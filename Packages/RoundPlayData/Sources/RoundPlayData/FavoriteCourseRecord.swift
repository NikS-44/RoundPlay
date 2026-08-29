import Foundation
import SwiftData

@Model
public final class FavoriteCourseRecord {
    public var openGolfID: String = ""
    public var name: String = ""
    public var city: String?
    public var state: String?
    public var favoritedAt: Date = Date()

    public init(openGolfID: String, name: String, city: String?, state: String?) {
        self.openGolfID = openGolfID
        self.name = name
        self.city = city
        self.state = state
    }
}
