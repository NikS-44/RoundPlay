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
                NavigationLink {
                    GameDetailView(metadata: metadata)
                } label: {
                    GameCard(metadata: metadata)
                }
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .navigationTitle("Games")
    }
}

struct GameCard: View {
    let metadata: GameMetadata

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: metadata.iconName)
                .font(.title2)
                .foregroundStyle(RoundPlayColors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    RoundPlayTypography.headline(metadata.displayName)
                    Spacer()
                    RoundPlayTypography.eyebrow(metadata.playerCountLabel)
                        .foregroundStyle(.secondary)
                }
                RoundPlayTypography.body(metadata.summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") { NavigationStack { GameLibraryView() } }
#Preview("Dark") {
    NavigationStack { GameLibraryView() }.preferredColorScheme(.dark)
}
