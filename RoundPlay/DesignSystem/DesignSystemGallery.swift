import SwiftUI

/// Scratch screen for eyeballing ported design system components in light and dark.
///
/// Temporary — Phase 1b replaces the Games tab with the real game library. Delete this file then.
struct DesignSystemGallery: View {
    var body: some View {
        RoundPlayList.plain {
            HubSectionLabel(title: "Buttons")
            Button("Accent Outline") {}.buttonStyle(AccentOutlineButtonStyle())
            Button("Destructive") {}.buttonStyle(RedOutlineButtonStyle())

            HubSectionLabel(title: "Chips")
            ChipButton(title: "Skins", isSelected: true) {}
            ChipButton(title: "Nassau", isSelected: false) {}

            HubSectionLabel(title: "Scoring colors")
            Text("Birdie").foregroundStyle(RoundPlayColors.scoreUnderPar)
            Text("Par").foregroundStyle(RoundPlayColors.scoreAtPar)
            Text("Bogey").foregroundStyle(RoundPlayColors.scoreOverPar)

            HubSectionLabel(title: "Connection")
            Text("Live").foregroundStyle(RoundPlayColors.connectionLive)
            Text("Syncing").foregroundStyle(RoundPlayColors.connectionSyncing)
            Text("Offline").foregroundStyle(RoundPlayColors.connectionOffline)
        }
        .navigationTitle("Design System")
    }
}

#Preview("Light") { NavigationStack { DesignSystemGallery() } }
#Preview("Dark") {
    NavigationStack { DesignSystemGallery() }.preferredColorScheme(.dark)
}
