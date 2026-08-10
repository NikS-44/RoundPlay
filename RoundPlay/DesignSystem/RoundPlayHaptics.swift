import SwiftUI

/// Semantic haptics for RoundPlay.
///
/// Everything routes through SwiftUI's `.sensoryFeedback`, never a raw
/// `UIImpactFeedbackGenerator` — the modifier respects the system's haptic settings and the user's
/// accessibility preferences for free, and SwiftUI owns the generator's lifecycle so nothing has
/// to be prepared or retained at the call site.
///
/// The vocabulary is deliberately tiny. A round is 18 holes × 4 players of tapping; if every tap
/// buzzed, the phone would feel broken by the third green. Feedback is reserved for the moments
/// where something was **committed** or **decided** — never for navigation, scrolling, or
/// appearance.
enum RoundPlayHaptics {
    /// A score was picked, a seat assigned, a count stepped. The workhorse — light and frequent.
    static let selection: SensoryFeedback = .selection

    /// A decision with money behind it: a game toggled on, a stake set, a Wolf partner named.
    /// Weightier than `selection` because these are the taps a group argues about later.
    static let decision: SensoryFeedback = .impact(weight: .medium)

    /// The round is finished, or the money is settled. Fires at most twice a round — that rarity
    /// is what makes it land.
    static let success: SensoryFeedback = .success

    /// The user tried to move on with holes still missing scores.
    static let warning: SensoryFeedback = .warning
}
