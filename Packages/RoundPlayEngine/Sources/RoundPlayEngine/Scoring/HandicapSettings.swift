import Foundation

/// How a group agreed to handle strokes for one round.
///
/// Frozen at round creation alongside the seats' course handicaps, for the same reason: a round
/// settles on the terms agreed when it started, and re-reading a live preference later would
/// silently restate money that has already changed hands.
public struct HandicapSettings: Codable, Sendable, Equatable {
    public var mode: StrokeMode
    /// Percentage of course handicap that becomes playing handicap. 100 means no reduction.
    ///
    /// The competition allowances (85% four-ball, 95% stroke play, 90% four-ball match) exist to
    /// keep high handicaps from dominating team formats. Most casual money games ignore them, so
    /// the default is 100 and the app surfaces this only under "Advanced".
    public var allowancePercent: Int
    /// House cap on the playing handicap. `nil` means uncapped.
    ///
    /// Not part of the Rules of Handicapping — it's the convention groups use to stop a 36 from
    /// being unbeatable in Skins.
    public var maxStrokes: Int?

    public static let `default` = HandicapSettings(mode: .offTheLow, allowancePercent: 100, maxStrokes: nil)

    public init(mode: StrokeMode = .offTheLow, allowancePercent: Int = 100, maxStrokes: Int? = nil) {
        self.mode = mode
        self.allowancePercent = allowancePercent
        self.maxStrokes = maxStrokes
    }
}

/// How strokes are shared out across the group.
public enum StrokeMode: String, Codable, Sendable, CaseIterable {
    /// The lowest handicap plays off scratch; everyone else receives the difference.
    ///
    /// The convention for every hole-by-hole money game — Skins, Nassau, Wolf, Match Play. Not
    /// interchangeable with `full`: strokes land in stroke-index order, so subtracting the low
    /// handicap changes *which* holes carry an edge, not just how many strokes exist.
    case offTheLow
    /// Everyone plays their whole playing handicap. Correct for stroke play and Stableford.
    case full
    /// No strokes at all — gross scores decide everything.
    case straightUp
}

/// Turns each seat's course handicap into the playing handicap actually used for allocation.
public enum PlayingHandicap {

    /// Playing handicap per player, keyed by player id.
    ///
    /// Order matters and is fixed: allowance, then cap, then mode. The cap applies to the playing
    /// handicap rather than to strokes received, so that capping and the allowance compose
    /// predictably instead of depending on which the group happened to set first.
    public static func byPlayer(seats: [Seat], settings: HandicapSettings) -> [UUID: Int] {
        guard settings.mode != .straightUp else {
            // Straight up means gross scores decide everything, so a hand-agreed number has
            // nothing to apply to either.
            return Dictionary(uniqueKeysWithValues: seats.map { ($0.playerID, 0) })
        }

        let allowed = seats.map { seat -> (UUID, Int) in
            // Plus handicaps are out of scope and clamp to zero, matching `HandicapAllocation`.
            let base = max(0, seat.courseHandicap)
            let afterAllowance = Int((Double(base) * Double(settings.allowancePercent) / 100).rounded())
            let capped = settings.maxStrokes.map { min(afterAllowance, max(0, $0)) } ?? afterAllowance
            return (seat.playerID, capped)
        }

        // The baseline comes from the derived values even when some seats are overridden — an
        // agreed number for one player shouldn't quietly move everyone else's strokes.
        let lowest = settings.mode == .offTheLow ? (allowed.map(\.1).min() ?? 0) : 0
        let derived = allowed.map { ($0.0, max(0, $0.1 - lowest)) }

        var result = Dictionary(uniqueKeysWithValues: derived)
        for seat in seats {
            if let override = seat.strokeOverride {
                result[seat.playerID] = max(0, override)
            }
        }
        return result
    }
}
