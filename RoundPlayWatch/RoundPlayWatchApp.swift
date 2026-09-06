import SwiftUI
import SwiftData
import RoundPlayData

@main
struct RoundPlayWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container = RoundPlaySchema.makeContainer()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(RoundSyncSession.shared)
                .onAppear {
                    #if DEBUG
                    // Screenshot and layout-check seeding, debug builds only and only when asked
                    // for by launch argument. `WatchDemoData` is itself entirely inside `#if
                    // DEBUG`, so nothing here exists in an App Store archive.
                    if WatchDemoData.isRequested {
                        WatchDemoData.seed(into: container.mainContext)
                    }
                    #endif
                    RoundSyncSession.shared.activate(context: container.mainContext)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { RoundSyncSession.shared.pushAll() }
                }
        }
        .modelContainer(container)
    }
}
