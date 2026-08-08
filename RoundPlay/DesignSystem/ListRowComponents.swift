import SwiftUI

// MARK: - Row press feedback

/// Opacity feedback for tappable list-style controls (use with `Button` / `.buttonStyle`).
struct ListRowPressOpacityStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
