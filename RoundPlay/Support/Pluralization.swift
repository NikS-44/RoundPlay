import Foundation

/// "1 round" / "2 rounds".
///
/// Hardcoded `"\(count) rounds"` reads as a bug the first time someone opens the roster after a
/// single round with a new player — and a solo round rendered "1 players" on three screens. This
/// is deliberately a plain helper rather than the `^[...](inflect: true)` markup: the app has no
/// localization catalog yet, and inflection silently falls back to the raw literal without one.
func pluralized(_ count: Int, _ singular: String, plural: String? = nil) -> String {
    let noun = count == 1 ? singular : (plural ?? singular + "s")
    return "\(count) \(noun)"
}
