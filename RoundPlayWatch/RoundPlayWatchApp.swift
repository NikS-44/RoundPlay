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
                    RoundSyncSession.shared.activate(context: container.mainContext)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { RoundSyncSession.shared.pushAll() }
                }
        }
        .modelContainer(container)
    }
}
