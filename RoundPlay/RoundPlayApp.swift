import SwiftUI
import SwiftData
import RoundPlayData

@main
struct RoundPlayApp: App {
    @UIApplicationDelegateAdaptor(RoundPlayAppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = RoundPlaySchema.appContainer

    var body: some Scene {
        WindowGroup {
            ContentView()
                .celebrationOverlay()
                .environment(RoundSyncSession.shared)
                .onAppear {
                    RoundSyncSession.shared.activate(context: sharedModelContainer.mainContext)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        RoundSyncSession.shared.pushAll()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
