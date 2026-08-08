import SwiftUI
import SwiftData

/// Three-step round setup: course, players, games.
struct NewRoundFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model = NewRoundModel()
    @State private var path = NavigationPath()

    let onStart: (RoundRecord) -> Void

    private enum Step: Hashable { case players, games }

    var body: some View {
        NavigationStack(path: $path) {
            CourseListView { course in
                model.course = course
                path.append(Step.players)
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .players:
                    PlayerSelectionStep(model: model) { path.append(Step.games) }
                case .games:
                    GameSetupView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Start") { start() }.disabled(!model.canStart)
                            }
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func start() {
        guard let round = model.makeRound(in: modelContext) else { return }
        onStart(round)
        dismiss()
    }
}

/// Who's playing. Roster first, sorted by recency — the regular group is at the top.
private struct PlayerSelectionStep: View {
    @Bindable var model: NewRoundModel
    let onContinue: () -> Void

    @Query(sort: [SortDescriptor(\PlayerRecord.lastPlayedAt, order: .reverse),
                  SortDescriptor(\PlayerRecord.name)])
    private var players: [PlayerRecord]

    @State private var isAddingPlayer = false

    var body: some View {
        RoundPlayList.plain {
            ForEach(players) { player in
                Button {
                    toggle(player)
                } label: {
                    HStack {
                        Image(systemName: isSelected(player) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isSelected(player) ? RoundPlayColors.accent : .secondary)
                        PlayerRow(player: player)
                    }
                }
                .buttonStyle(RoundPlayRowButtonStyle())
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Players")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New", systemImage: "plus") { isAddingPlayer = true }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next", action: onContinue)
                    .disabled(model.selectedPlayers.count < 2)
            }
        }
        .sheet(isPresented: $isAddingPlayer) {
            NavigationStack {
                PlayerEditSheet(player: nil) { model.selectedPlayers.append($0) }
            }
        }
    }

    private func isSelected(_ player: PlayerRecord) -> Bool {
        model.selectedPlayers.contains { $0.id == player.id }
    }

    private func toggle(_ player: PlayerRecord) {
        if isSelected(player) {
            model.selectedPlayers.removeAll { $0.id == player.id }
        } else {
            model.selectedPlayers.append(player)
        }
    }
}

#Preview("Light") {
    NewRoundFlowView { _ in }.modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NewRoundFlowView { _ in }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
