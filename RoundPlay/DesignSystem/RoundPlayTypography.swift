import SwiftUI

/// RoundPlay's two-typeface system: **Archivo** for display, headings, and UI copy; **IBM Plex
/// Mono** for anything that reads as data — codes, eyebrow labels, and money. Money sits on the
/// mono face (not Archivo) so amounts read as a ledger even outside the ledger screen itself.
///
/// Font files live in `Resources/Fonts/` and are registered via `UIAppFonts` in project.yml.
enum RoundPlayFont {
    enum Weight {
        case regular, medium, semiBold, bold, black

        fileprivate var postscriptName: String {
            switch self {
            case .regular: "Archivo-Regular"
            case .medium: "Archivo-Medium"
            case .semiBold: "Archivo-SemiBold"
            case .bold: "Archivo-Bold"
            case .black: "Archivo-Black"
            }
        }
    }

    enum MonoWeight {
        case regular, medium, semiBold

        fileprivate var postscriptName: String {
            switch self {
            case .regular: "IBMPlexMono-Regular"
            case .medium: "IBMPlexMono-Medium"
            case .semiBold: "IBMPlexMono-SemiBold"
            }
        }
    }

    static func archivo(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom(weight.postscriptName, size: size)
    }

    static func plexMono(_ size: CGFloat, _ weight: MonoWeight = .medium) -> Font {
        .custom(weight.postscriptName, size: size)
    }
}

/// Named text styles matching the brand kit's type spec, as `Text` factories so tracking rides
/// along with the font (SwiftUI has no single `Font` property for letterspacing).
enum RoundPlayTypography {

    /// Hero numeral — the hole number on `HoleHeader`. 64pt Archivo Black, tight tracking.
    static func hero(_ text: String) -> Text {
        Text(text)
            .font(RoundPlayFont.archivo(64, .black))
            .tracking(-3.2)
    }

    /// Screen title ("Rounds", "Standings", "Settings"). 34pt Archivo Black.
    static func largeTitle(_ text: String) -> Text {
        Text(text)
            .font(RoundPlayFont.archivo(34, .black))
            .tracking(-1.2)
    }

    /// Card headline ("Torrey Pines South"). 23pt Archivo Black.
    static func title(_ text: String) -> Text {
        Text(text)
            .font(RoundPlayFont.archivo(23, .black))
            .tracking(-0.46)
    }

    /// Row/section headline ("Skins", a player's name). 17pt Archivo Bold.
    static func headline(_ text: String) -> Text {
        Text(text).font(RoundPlayFont.archivo(17, .bold))
    }

    /// Body copy. 16pt Archivo Regular.
    static func body(_ text: String) -> Text {
        Text(text).font(RoundPlayFont.archivo(16, .regular))
    }

    /// Secondary/meta line (handicap, round count). 13pt Archivo Regular.
    static func caption(_ text: String) -> Text {
        Text(text).font(RoundPlayFont.archivo(13, .regular))
    }

    /// Uppercase micro-label ("IN PROGRESS", "STEP 1 OF 3", "HOLE"). IBM Plex Mono, wide tracking.
    static func eyebrow(_ text: String) -> Text {
        Text(text.uppercased())
            .font(RoundPlayFont.plexMono(9.5, .medium))
            .tracking(1.4)
    }

    /// Score-strip digit / hole/par/SI figure. Archivo Bold, tabular.
    static func numeral(_ text: String, size: CGFloat = 21, weight: RoundPlayFont.Weight = .bold) -> Text {
        Text(text).font(RoundPlayFont.archivo(size, weight))
    }

    /// A money amount ("+$14.00"). IBM Plex Mono — money always reads as ledger data.
    static func money(_ text: String, size: CGFloat = 15, weight: RoundPlayFont.MonoWeight = .semiBold) -> Text {
        Text(text).font(RoundPlayFont.plexMono(size, weight))
    }

    /// A share code / join code ("otter-maple-jump"). IBM Plex Mono Medium.
    static func code(_ text: String, size: CGFloat = 17) -> Text {
        Text(text).font(RoundPlayFont.plexMono(size, .medium))
    }
}
