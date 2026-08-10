import SwiftUI
import SwiftData

@main
struct RoundPlayApp: App {
    @UIApplicationDelegateAdaptor(RoundPlayAppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = RoundPlaySchema.appContainer

    var body: some Scene {
        WindowGroup {
            // Applied at the root so the fireworks cover the whole window rather than being
            // clipped to whatever sheet or tab happened to trigger them.
            ContentView()
                .celebrationOverlay()
        }
        .modelContainer(sharedModelContainer)
    }
}
