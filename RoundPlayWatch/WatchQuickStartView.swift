import SwiftUI
import SwiftData
import RoundPlayEngine
import RoundPlayData

struct WatchQuickStartView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\CourseRecord.lastPlayedAt, order: .reverse)])
    private var courses: [CourseRecord]
    @Query(sort: [SortDescriptor(\PlayerRecord.playCount, order: .reverse)])
    private var players: [PlayerRecord]
    @Query(sort: \RoundRecord.startedAt, order: .reverse)
    private var rounds: [RoundRecord]

    @State private var selectedCourse: CourseRecord?
    @State private var selectedPlayerIDs: Set<UUID> = []
    @State private var selectedGameTypes: Set<GameType> = []
    @State private var stake: Decimal = 2
    @State private var copyPrevious = true
    @State private var step = 0

    private var playableCourses: [CourseRecord] {
        courses.filter { $0.engineCourse != nil }
    }

    private var selectedPlayers: [PlayerRecord] {
        players.filter { selectedPlayerIDs.contains($0.id) }
    }

    private var matchingRound: RoundRecord? {
        PreviousRoundMatch.find(playerIDs: selectedPlayerIDs, in: rounds)
    }

    var body: some View {
        Group {
            switch step {
            case 0: courseStep
            case 1: playerStep
            case 2: gamesStep
            default: courseStep
            }
        }
        .navigationTitle("New Round")
    }

    private var courseStep: some View {
        List {
            if playableCourses.isEmpty {
                Text("No courses yet. Add one on your phone.")
                    .foregroundStyle(.secondary)
            }
            ForEach(playableCourses) { course in
                Button(course.name) {
                    selectedCourse = course
                    step = 1
                }
            }
        }
    }

    private var playerStep: some View {
        List {
            ForEach(players) { player in
                Button {
                    if selectedPlayerIDs.contains(player.id) {
                        selectedPlayerIDs.remove(player.id)
                    } else {
                        selectedPlayerIDs.insert(player.id)
                    }
                } label: {
                    HStack {
                        Text(player.name)
                        Spacer()
                        if selectedPlayerIDs.contains(player.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if let match = matchingRound, selectedPlayerIDs.count >= 2 {
                Button("Same as last — \(PreviousRoundMatch.summary(match))") {
                    copyPrevious = true
                    start(copying: match)
                }
                .foregroundStyle(WatchPalette.accent)
            }
            Button("Continue") { step = 2 }
                .disabled(selectedCourse == nil || selectedPlayers.count < 1)
        }
    }

    private var gamesStep: some View {
        let eligible = GameLibrary.all.filter { $0.playerRange.contains(selectedPlayers.count) }
        return List {
            ForEach(eligible) { meta in
                Button {
                    if selectedGameTypes.contains(meta.gameType) {
                        selectedGameTypes.remove(meta.gameType)
                    } else {
                        selectedGameTypes.insert(meta.gameType)
                    }
                } label: {
                    HStack {
                        Text(meta.displayName)
                        Spacer()
                        if selectedGameTypes.contains(meta.gameType) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Section("Stake") {
                ForEach(WatchGameDefaults.stakePresets, id: \.self) { preset in
                    Button { stake = preset } label: {
                        Text(verbatim: "$\(preset)")
                    }
                        .foregroundStyle(preset == stake ? WatchPalette.accent : .primary)
                }
            }
            Button("Start round") { start(copying: nil) }
                .disabled(selectedCourse == nil || selectedPlayers.isEmpty)
        }
    }

    private func start(copying previous: RoundRecord?) {
        guard let course = selectedCourse else { return }
        let configs: [GameConfiguration]
        if let previous, copyPrevious {
            configs = (previous.games ?? []).compactMap(\.configuration)
        } else {
            configs = selectedGameTypes.map { WatchGameDefaults.configuration(for: $0, stake: stake) }
        }
        _ = WatchRoundFactory.makeRound(
            course: course,
            players: selectedPlayers,
            configurations: configs,
            copyingHandicapsFrom: previous,
            in: modelContext
        )
    }
}
