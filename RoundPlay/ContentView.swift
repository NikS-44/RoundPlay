import SwiftUI

/// Root tab shell.
///
/// Tabs map to the three things a user does: start or resume a round, browse the game
/// library, and manage their roster of playing companions.
struct ContentView: View {
    @AppStorage(AppearancePreference.appStorageKey)
    private var appearancePreferenceRaw = AppearancePreference.system.rawValue
    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearancePreferenceRaw) ?? .system
    }

    private enum AppTab: Hashable { case rounds, games, players }
    @State private var selectedTab: AppTab = .rounds
    @State private var pendingStartFavorite: OpenGolfCourse?
    @State private var pendingStartRound = false
    @State private var isShowingOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Rounds", systemImage: "flag.circle", value: AppTab.rounds) {
                NavigationStack {
                    RoundsHomeView(autoStartFavorite: $pendingStartFavorite, autoStartRound: $pendingStartRound)
                }
            }
            Tab("Games", systemImage: "list.bullet.rectangle", value: AppTab.games) {
                NavigationStack { GameLibraryView() }
            }
            Tab("Roster", systemImage: "person.2", value: AppTab.players) {
                NavigationStack { PlayerListView() }
            }
        }
        .preferredColorScheme(appearancePreference.colorScheme)
        .task {
            if !hasCompletedOnboarding { isShowingOnboarding = true }
        }
        .fullScreenCover(isPresented: $isShowingOnboarding) {
            OnboardingFlowView { action in
                hasCompletedOnboarding = true
                isShowingOnboarding = false
                switch action {
                case .explore:
                    selectedTab = .rounds
                case .startRound(let favorite):
                    selectedTab = .rounds
                    pendingStartFavorite = favorite
                    pendingStartRound = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
