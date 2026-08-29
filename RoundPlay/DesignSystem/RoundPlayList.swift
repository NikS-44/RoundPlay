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

    /// `plain`, with the list's scroll proxy handed to the content.
    ///
    /// For screens that reveal something below the fold — an expanding disclosure group, say —
    /// and have to bring it into view themselves. Separately named rather than overloaded so no
    /// call site has to think about which one a trailing closure resolves to.
    @MainActor
    @ViewBuilder
    static func plainScrolling<Content: View>(
        @ViewBuilder content: @escaping (ScrollViewProxy) -> Content
    ) -> some View {
        ScrollViewReader { proxy in
            SwiftUI.List {
                content(proxy)
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

extension View {
    /// By default SwiftUI insets list row separators to align with the title, leaving a gap under
    /// leading icons or checkboxes. Use on the **root** view of each list row (`HStack` /
    /// `NavigationLink` / `Button` row) to make the separator run full-width instead.
    func roundPlayListRowSeparatorFullWidth() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    /// Primary actions keep their hierarchy without creating a bright filled block in dark mode.
    @MainActor
    func roundPlayPrimaryButtonStyle() -> some View {
        modifier(RoundPlayPrimaryButtonModifier())
    }
}

private struct RoundPlayPrimaryButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.buttonStyle(RoundPlayDarkPrimaryButtonStyle())
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

/// The dark-mode primary action.
///
/// The accent is a bright mint in dark mode, which rules out both system styles. `.borderedProminent`
/// paints a full mint block with a white label — glare, and the label barely separates from its own
/// fill. `.bordered` goes the other way: a neutral grey system fill that reads as a disabled chip,
/// with nothing but the label colour to say it is the primary action. What was missing is an edge.
/// An accent wash gives the shape a body, an accent border draws it, and the label sits in the same
/// accent, so the button reads as primary without lighting up the page.
struct RoundPlayDarkPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    private var foreground: Color {
        isEnabled ? RoundPlayColors.accent : Color(uiColor: .tertiaryLabel)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            // Floors a label-sized button at a comfortable tap target while leaving the taller
            // full-width bars (which set their own `minHeight`) untouched.
            .frame(minHeight: 28)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(RoundPlayColors.accent.opacity(isEnabled ? 0.18 : 0.06))
            )
            .overlay(
                Capsule().strokeBorder(foreground.opacity(isEnabled ? 0.9 : 0.25), lineWidth: 1.5)
            )
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
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
