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
            // The sync glyph used to sit in the bar's leading slot. The hole screen needs that
            // slot for its own back/forward arrows, and a connectivity dot is worth less on the
            // scoring screen than the two controls used on every hole.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if activeRound == nil {
                        SyncStatusGlyph(state: sync.connectionState)
                    }
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
            WatchStandingsView(round: round, course: course)
            WatchScorecardView(round: round, course: course)
        }
        .tabViewStyle(.verticalPage)
        // No title: the course name used to live here and was drawn over the top of the hole
        // screen's own header — "Pebble Creek" landing on "1 of 1" — and once you've teed off you
        // already know what course you're standing on.
        //
        // No tab labels either. They never rendered as text in a vertical pager, but the pages
        // reserved a header line for them, which was the empty band above the hole number.
    }
}
