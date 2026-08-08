import SwiftUI
import SwiftData

@main
struct RoundPlayApp: App {
    @UIApplicationDelegateAdaptor(RoundPlayAppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = RoundPlaySchema.appContainer

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
