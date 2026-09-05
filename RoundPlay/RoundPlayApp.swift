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
                    #if DEBUG
                    // Screenshot seeding, debug builds only and only when asked for by launch
                    // argument. `DemoData` is itself entirely inside `#if DEBUG`, so nothing here
                    // exists in an App Store archive.
                    if DemoData.isRequested {
                        DemoData.seed(into: sharedModelContainer.mainContext)
                    }
                    #endif
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
