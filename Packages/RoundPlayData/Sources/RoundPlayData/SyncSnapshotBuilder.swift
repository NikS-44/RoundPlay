import Foundation
import SwiftData

public enum SyncSnapshotBuilder {
    public static let recentCompletedLimit = 5

    public static func roster(from context: ModelContext) throws -> RosterPayload {
        RosterPayload(players: try context.fetch(FetchDescriptor<PlayerRecord>()).map(PlayerSnapshot.init))
    }

    public static func courses(from context: ModelContext) throws -> CoursesPayload {
        let allCourses = try context.fetch(FetchDescriptor<CourseRecord>())
        let playable = allCourses.filter { $0.pars.count == 18 }
        let recent = playable
            .filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        let favorites = try context.fetch(FetchDescriptor<FavoriteCourseRecord>())
        let favoriteIDs = Set(favorites.compactMap(\.openGolfID))
        let favoriteCourses = playable.filter { course in
            guard let openID = course.openGolfID else { return false }
            return favoriteIDs.contains(openID)
        }
        var byID: [UUID: CourseRecord] = [:]
        for course in recent + favoriteCourses {
            byID[course.id] = course
        }
        return CoursesPayload(
            courses: Array(byID.values).map(CourseSnapshot.init),
            favorites: favorites.map(FavoriteSnapshot.init)
        )
    }

    public static func rounds(from context: ModelContext) throws -> RoundsPayload {
        let all = try context.fetch(FetchDescriptor<RoundRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        let active = all.filter { !$0.isComplete && !$0.isDeleted }
        let recentCompleted = all.filter { $0.isComplete && !$0.isDeleted }.prefix(recentCompletedLimit)
        return RoundsPayload(rounds: (active + recentCompleted).map(RoundSnapshot.init))
    }
}
