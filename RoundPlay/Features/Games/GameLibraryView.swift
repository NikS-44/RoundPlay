import SwiftUI
import RoundPlayEngine

/// The six games, with plain-English explanations.
///
/// Copy comes from `GameMetadata.summary` — defined next to each engine's rules, so a rule change
/// and its description move together.
struct GameLibraryView: View {
    var body: some View {
        RoundPlayList.plain {
            ForEach(GameLibrary.all) { metadata in
                GameCard(metadata: metadata)
                    .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Games")
    }
}

struct GameCard: View {
    let metadata: GameMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metadata.displayName).font(.headline)
                Spacer()
                Text(metadata.playerCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(metadata.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") { NavigationStack { GameLibraryView() } }
#Preview("Dark") {
    NavigationStack { GameLibraryView() }.preferredColorScheme(.dark)
}
