import SwiftUI
import SwiftData
import RoundPlayData
import RoundPlayEngine

struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RoundSyncSession.self) private var sync
    @Query(sort: \RoundRecord.startedAt, order: .reverse) private var rounds: [RoundRecord]
    @Query private var courses: [CourseRecord]

    private var activeRound: RoundRecord? {
        rounds.first { !$0.isComplete && !$0.isDeleted }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let round = activeRound, let course = courses.first(where: { $0.id == round.courseID })?.engineCourse {
                    WatchRoundPager(round: round, course: course)
                } else {
                    WatchQuickStartView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusGlyph(state: sync.connectionState)
                }
            }
        }
    }
}

struct WatchRoundPager: View {
    let round: RoundRecord
    let course: Course

    var body: some View {
        TabView {
            WatchHoleEntryView(round: round, course: course)
                .tabItem { Text("Hole") }
            WatchStandingsView(round: round, course: course)
                .tabItem { Text("Stand") }
            WatchScorecardView(round: round, course: course)
                .tabItem { Text("Card") }
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
