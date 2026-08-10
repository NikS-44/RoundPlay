import Foundation
import CoreLocation

/// Loads and searches the bundled OpenGolf course dataset.
///
/// The whole US dataset (~15.7k rows) is small enough to hold in memory once decoded — no
/// database engine needed for a proof of concept at this scale. Decoding happens once, off the
/// main thread, on first use; `JSONDecoder` against a positional (non-keyed) encoding is both
/// simpler and faster than the hand-rolled CSV parser this replaced.
@MainActor
@Observable
final class OpenGolfCourseCatalog {
    static let shared = OpenGolfCourseCatalog()

    private(set) var courses: [OpenGolfCourse] = []
    private(set) var isLoaded = false
    private(set) var isLoading = false

    /// Name lowercased once at load time, parallel to `courses` — avoids re-lowercasing all
    /// ~15.7k names on every keystroke while typing a search.
    private var searchIndex: [(course: OpenGolfCourse, haystack: String)] = []

    private init() {}

    func load() async {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        let parsed = await Task.detached(priority: .userInitiated) {
            Self.decodeBundledJSON()
        }.value
        courses = parsed
        searchIndex = parsed.map { course in
            (course, [course.name, course.city ?? "", course.state ?? ""].joined(separator: " ").lowercased())
        }
        isLoaded = true
        isLoading = false
    }

    /// Case-insensitive match on course name, city, or state. When location is available,
    /// proximity is the primary sort so a search for a common name returns the nearby course
    /// first instead of making the user scan alphabetical results.
    func search(_ query: String, nearestTo location: CLLocation? = nil) -> [OpenGolfCourse] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let matches = searchIndex.filter { $0.haystack.contains(needle) }.map(\.course)
        guard let location else {
            return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return matches.sorted {
            let firstDistance = location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            let secondDistance = location.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            if firstDistance == secondDistance {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return firstDistance < secondDistance
        }
    }

    /// Nearest courses to a location, closest first.
    func nearest(to location: CLLocation, limit: Int = 20) -> [OpenGolfCourse] {
        courses
            .map { course in
                (course, location.distance(from: CLLocation(latitude: course.latitude, longitude: course.longitude)))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func course(id: String) -> OpenGolfCourse? {
        courses.first { $0.id == id }
    }

    private nonisolated static func decodeBundledJSON() -> [OpenGolfCourse] {
        guard let url = Bundle.main.url(forResource: "opengolfapi-us", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? JSONDecoder().decode([OpenGolfCourse].self, from: data)) ?? []
    }
}
