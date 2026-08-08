import SwiftUI
import SwiftData
import RoundPlayEngine

/// The Rounds tab: start a round, or resume one in progress.
struct RoundsHomeView: View {
    @Query(sort: \RoundRecord.startedAt, order: .reverse) private var rounds: [RoundRecord]
    @Query private var courses: [CourseRecord]

    @State private var isCreatingRound = false
    @State private var activeRound: RoundRecord?

    private func course(for round: RoundRecord) -> Course? {
        courses.first { $0.id == round.courseID }?.engineCourse
    }

    var body: some View {
        RoundPlayList.plain {
            if rounds.isEmpty {
                ContentUnavailableView(
                    "No rounds yet",
                    systemImage: "flag.circle",
                    description: Text("Start a round and keep score for your group.")
                )
            }

            ForEach(rounds) { round in
                NavigationLink {
                    if let course = course(for: round) {
                        RoundTabsView(round: round, course: course)
                    } else {
                        ContentUnavailableView(
                            "Course unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text("The course for this round is missing or incomplete.")
                        )
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(round.courseName).font(.body)
                        Text("\(round.orderedSeats.count) players · \(round.startedAt, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Rounds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Round", systemImage: "plus") { isCreatingRound = true }
            }
        }
        .sheet(isPresented: $isCreatingRound) {
            NewRoundFlowView { activeRound = $0 }
        }
    }
}

/// Scoring and standings for a round in progress.
struct RoundTabsView: View {
    let round: RoundRecord
    let course: Course

    var body: some View {
        TabView {
            Tab("Scorecard", systemImage: "square.grid.3x3") {
                NavigationStack { HoleScreenView(round: round, course: course) }
            }
            Tab("Standings", systemImage: "chart.bar") {
                NavigationStack { RoundDashboardView(round: round, course: course) }
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { RoundsHomeView() }.modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { RoundsHomeView() }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
