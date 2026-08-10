import Foundation
import SwiftData

/// A starred course from the OpenGolf catalog. Denormalizes name/city/state so favorites render
/// without re-parsing the bundled CSV, and exists independently of `CourseRecord` — you can
/// favorite a course before ever playing (or fully entering) it.
@Model
final class FavoriteCourseRecord {
    var openGolfID: String = ""
    var name: String = ""
    var city: String?
    var state: String?
    var favoritedAt: Date = Date()

    init(openGolfID: String, name: String, city: String?, state: String?) {
        self.openGolfID = openGolfID
        self.name = name
        self.city = city
        self.state = state
    }
}
