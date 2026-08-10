import SwiftUI
import UIKit

/// Semantic colors for RoundPlay. Prefer these over raw `.red`, `.green`, etc. in feature code.
///
/// Tokens may share values, but the names let us retune one meaning without touching the others.
/// Every token must be legible in **both** light and dark — the app is used outdoors in direct
/// sun, where low-contrast greys disappear entirely.
enum RoundPlayColors {

    // MARK: - Brand

    /// App accent — fairway green, from `Assets.xcassets/AccentColor`.
    static let accent = Color.accentColor

    /// Board — the fixed near-black surface for featured/live cards and the hole header.
    /// Stays dark in both light and dark mode; it's a branded chrome color, not a system one.
    static let board = Color(red: 0.055, green: 0.082, blue: 0.071)

    /// Paper — cream text/foreground for content sitting on `board`. Fixed, not dynamic, for the
    /// same reason `board` is fixed: the two are always paired.
    static let paperOnBoard = Color(red: 0.961, green: 0.953, blue: 0.933)

    /// Pin — amber for "live/in progress" status text and badges.
    static let pin = Color(red: 0.878, green: 0.639, blue: 0.180)

    /// Page background — warm paper in light mode, system default in dark mode.
    static let pageBackground = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? .systemBackground
            : UIColor(red: 0.961, green: 0.953, blue: 0.933, alpha: 1)
    })

    // MARK: - Scoring

    /// Score at or under par.
    static let scoreUnderPar = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.82, blue: 0.55, alpha: 1)
            : UIColor(red: 0.09, green: 0.52, blue: 0.28, alpha: 1)
    })
    /// Score at par — deliberately neutral so birdies and blowups are what catch the eye.
    static let scoreAtPar = Color.primary
    /// Score over par.
    static let scoreOverPar = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.52, blue: 0.48, alpha: 1)
            : UIColor(red: 0.75, green: 0.20, blue: 0.16, alpha: 1)
    })
    /// The hole currently being scored.
    static let holeActive = Color.accentColor
    /// A hole with no score entered yet.
    static let holePending = Color(uiColor: .tertiaryLabel)

    // MARK: - Money

    /// Player is up money.
    static let moneyPositive = scoreUnderPar
    /// Player is down money.
    static let moneyNegative = scoreOverPar
    /// Player is even.
    static let moneyEven = Color.secondary
    /// Payments not yet available — the greyed-out Settle Up affordance.
    static let moneyDisabled = Color(uiColor: .quaternaryLabel)

    /// Money on the `board` surface. `board` stays dark regardless of system appearance, so text
    /// on it must always use the brighter, dark-mode-legible tones — `moneyPositive`/
    /// `moneyNegative` swap to darker greens/reds in light mode for a *light* background, which
    /// reads as low-contrast (measured ~3.95:1, under the 4.5:1 text minimum) against `board`.
    static let moneyPositiveOnBoard = Color(red: 0.40, green: 0.82, blue: 0.55)
    static let moneyNegativeOnBoard = Color(red: 1.00, green: 0.52, blue: 0.48)

    // MARK: - Connection state

    /// Socket open, outbox empty.
    static let connectionLive = scoreUnderPar
    /// Reachable, outbox draining.
    static let connectionSyncing = Color(red: 0.878, green: 0.541, blue: 0.118)
    /// Unreachable — scores are queued locally.
    static let connectionOffline = scoreOverPar

    // MARK: - Destructive

    static let destructive = Color.red

    // MARK: - Fills

    /// Primary "chip/card on a list background" fill; respects light/dark.
    static let fillSecondary = Color(uiColor: .secondarySystemFill)
    /// Lighter fill for layered chips on a card that already uses `fillSecondary`.
    static let fillTertiary = Color(uiColor: .tertiarySystemFill)
    /// Grouped-list / card background.
    static let backgroundSecondaryGrouped = Color(uiColor: .secondarySystemBackground)
    /// Page background.
    static let backgroundSystem = Color(uiColor: .systemBackground)
}
