import SwiftUI

// MARK: - Explicit SwiftUI.List wrapper

/// Thin wrapper over `SwiftUI.List` that centralizes the list-style and keyboard-dismiss settings
/// used across every list screen in the app, so they cannot drift between screens.
enum RoundPlayList {
    @MainActor
    @ViewBuilder
    static func plain<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        SwiftUI.List {
            content()
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
    }
}

extension View {
    /// By default SwiftUI insets list row separators to align with the title, leaving a gap under
    /// leading icons or checkboxes. Use on the **root** view of each list row (`HStack` /
    /// `NavigationLink` / `Button` row) to make the separator run full-width instead.
    func roundPlayListRowSeparatorFullWidth() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

/// Press feedback for list rows that navigate but are not `NavigationLink`s — plain `Button` rows
/// and `.onTapGesture` rows draw no highlight on touch, so they read as dead. Use on any row that
/// pushes a destination or opens a sheet so the tap is acknowledged the moment the finger lands.
struct RoundPlayRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RoundPlayColors.fillSecondary)
                    .opacity(configuration.isPressed ? 1 : 0)
                    // Bleed past the row's content insets so the highlight reads as a row, not a chip.
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
