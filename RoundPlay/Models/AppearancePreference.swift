import SwiftUI

/// User-selected light/dark override, persisted in `UserDefaults` via `@AppStorage`.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let appStorageKey = "appearancePreference"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
