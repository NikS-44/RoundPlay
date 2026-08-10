import Foundation
import CoreLocation

/// One course from the bundled OpenGolf dataset (`Resources/Data/opengolfapi-us.csv`).
///
/// Not a SwiftData `@Model` — this is reference data parsed once into memory, not something the
/// app owns or edits. Only what the user *does* with a course (favorite it, play it) becomes a
/// persisted record; the catalog itself is read-only.
///
/// The per-hole arrays are sparse by design: the source data's hole-by-hole breakdown is
/// frequently incomplete even for real 18-hole courses (see the plan doc), so callers must not
/// assume every entry is present.
struct OpenGolfCourse: Identifiable, Sendable, Equatable, Decodable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String
    let state: String?
    let city: String?
    let type: String?
    let totalPar: Int?
    let phone: String?
    let website: String?
    let yearBuilt: Int?
    let address: String?
    let postalCode: String?
    let architect: String?
    /// Index 0 is hole 1. `nil` where the source has no value for that hole.
    let holePars: [Int?]
    let holeHandicaps: [Int?]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var cityState: String? {
        switch (city, state) {
        case let (city?, state?): "\(city), \(state)"
        case let (city?, nil): city
        case let (nil, state?): state
        default: nil
        }
    }

    /// A catalog record is safe to use without manual verification only when it contains a
    /// complete, valid scorecard. Sparse records are still useful for search, but their missing
    /// values must not be silently replaced with placeholders before net scoring.
    var hasCompleteScorecard: Bool {
        holePars.count == 18
            && holePars.allSatisfy { par in par.map { (3...6).contains($0) } ?? false }
            && holeHandicaps.count == 18
            && Set(holeHandicaps.compactMap { $0 }) == Set(1...18)
    }

    /// Decodes from the bundled `opengolfapi-us.json`, which stores each course as a positional
    /// array (not keyed fields) to keep the bundle small and decoding fast — field names would
    /// otherwise repeat ~15,700 times over. Column order is fixed by the export script; see
    /// `docs/plans/2026-08-09-golf-course-data-import.md`.
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        name = try container.decode(String.self)
        latitude = try container.decode(Double.self)
        longitude = try container.decode(Double.self)
        country = try container.decode(String.self)
        state = try container.decode(String?.self)
        city = try container.decode(String?.self)
        type = try container.decode(String?.self)
        totalPar = try container.decode(Int?.self)
        phone = try container.decode(String?.self)
        website = try container.decode(String?.self)
        yearBuilt = try container.decode(Int?.self)
        address = try container.decode(String?.self)
        postalCode = try container.decode(String?.self)
        architect = try container.decode(String?.self)
        holePars = try container.decode([Int?].self)
        holeHandicaps = try container.decode([Int?].self)
    }
}
