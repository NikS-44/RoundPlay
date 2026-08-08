import SwiftUI
import SwiftData

/// Your roster of playing companions, most recent first.
struct PlayerListView: View {
    @Query(sort: [SortDescriptor(\PlayerRecord.lastPlayedAt, order: .reverse),
                  SortDescriptor(\PlayerRecord.name)])
    private var players: [PlayerRecord]

    @Environment(\.modelContext) private var modelContext
    @State private var editingPlayer: PlayerRecord?
    @State private var isAddingPlayer = false

    var body: some View {
        RoundPlayList.plain {
            if players.isEmpty {
                ContentUnavailableView(
                    "No players yet",
                    systemImage: "person.2",
                    description: Text("Add the people you play with. They'll be one tap away next round.")
                )
            }

            ForEach(players) { player in
                Button {
                    editingPlayer = player
                } label: {
                    PlayerRow(player: player)
                }
                .buttonStyle(RoundPlayRowButtonStyle())
                .roundPlayListRowSeparatorFullWidth()
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Players")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isAddingPlayer = true }
            }
        }
        .sheet(isPresented: $isAddingPlayer) {
            NavigationStack { PlayerEditSheet(player: nil) { _ in } }
        }
        .sheet(item: $editingPlayer) { player in
            NavigationStack { PlayerEditSheet(player: player) { _ in } }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(players[index]) }
        try? modelContext.save()
    }
}

/// Name, handicap, and how often you play together.
struct PlayerRow: View {
    let player: PlayerRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                if let handicap = player.handicapIndex {
                    Text("Handicap \(handicap, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No handicap")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if player.playCount > 0 {
                Text("\(player.playCount) rounds")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { PlayerListView() }.modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { PlayerListView() }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
