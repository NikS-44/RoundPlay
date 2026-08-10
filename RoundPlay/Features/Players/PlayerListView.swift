import SwiftUI
import SwiftData

/// Your roster of playing companions, the people you play with most at the top.
///
/// Sorted by rounds played rather than recency, matching the round builder's roster step. Each row
/// shows its round count, so ordering by anything else made the list look unsorted — "28 rounds, 4
/// rounds, 1 round, 7 rounds" reads as a bug even when the recency order behind it is correct.
struct PlayerListView: View {
    @Query(sort: [SortDescriptor(\PlayerRecord.playCount, order: .reverse),
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
        .navigationTitle("Roster")
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

    private var initials: String {
        let parts = player.name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(RoundPlayFont.archivo(13, .bold))
                .foregroundStyle(RoundPlayColors.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(RoundPlayColors.fillSecondary))

            VStack(alignment: .leading, spacing: 2) {
                RoundPlayTypography.headline(player.name)
                if let handicap = player.handicapIndex {
                    Text("Handicap \(handicap, specifier: "%.1f")")
                        .font(RoundPlayFont.archivo(13))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No handicap")
                        .font(RoundPlayFont.archivo(13))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if player.playCount > 0 {
                Text(pluralized(player.playCount, "round"))
                    .font(RoundPlayFont.archivo(13))
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
