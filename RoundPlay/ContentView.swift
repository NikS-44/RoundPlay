import SwiftUI

/// Root tab shell.
///
/// Tabs map to the three things a user does: start or resume a round, browse the game
/// library, and manage their roster of playing companions.
struct ContentView: View {
    @AppStorage(AppearancePreference.appStorageKey)
    private var appearancePreferenceRaw = AppearancePreference.system.rawValue

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearancePreferenceRaw) ?? .system
    }

    var body: some View {
        TabView {
            Tab("Rounds", systemImage: "flag.circle") {
                NavigationStack { Text("Rounds").navigationTitle("Rounds") }
            }
            Tab("Games", systemImage: "list.bullet.rectangle") {
                NavigationStack { GameLibraryView() }
            }
            Tab("Players", systemImage: "person.2") {
                NavigationStack { PlayerListView() }
            }
        }
        .preferredColorScheme(appearancePreference.colorScheme)
    }
}

#Preview {
    ContentView()
}
