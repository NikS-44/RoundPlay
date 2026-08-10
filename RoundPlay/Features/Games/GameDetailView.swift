import SwiftUI
import SwiftData
import RoundPlayEngine

/// Full rules for one game, with a direct path into starting a round playing it.
struct GameDetailView: View {
    let metadata: GameMetadata
    @State private var isStartingRound = false
    @State private var startedRound: RoundRecord?

    @Query private var courses: [CourseRecord]

    private func course(for round: RoundRecord) -> Course? {
        courses.first { $0.id == round.courseID }?.engineCourse
    }

    private var paragraphs: [String] {
        metadata.rules
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: metadata.iconName)
                        .font(.largeTitle)
                        .foregroundStyle(RoundPlayColors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        RoundPlayTypography.title(metadata.displayName)
                        RoundPlayTypography.eyebrow(metadata.playerCountLabel)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        RoundPlayTypography.body(paragraph)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    isStartingRound = true
                } label: {
                    Text("Start a Round")
                        .font(RoundPlayFont.archivo(17, .semiBold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .roundPlayPrimaryButtonStyle()
                .tint(RoundPlayColors.accent)
                .padding(.top, 8)
            }
            .padding(20)
        }
        .navigationTitle(metadata.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isStartingRound) {
            NewRoundFlowView(preselectedGameType: metadata.gameType) { round in
                startedRound = round
            }
        }
        .navigationDestination(item: $startedRound) { round in
            if let course = course(for: round) {
                RoundTabsView(round: round, course: course)
            } else {
                ContentUnavailableView(
                    "Course unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The course for this round is missing or incomplete.")
                )
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { GameDetailView(metadata: GameLibrary.metadata(for: .skins)) }
}
#Preview("Dark") {
    NavigationStack { GameDetailView(metadata: GameLibrary.metadata(for: .wolf)) }
        .preferredColorScheme(.dark)
}
