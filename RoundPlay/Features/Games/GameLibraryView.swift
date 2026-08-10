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

/// One game's symbol, normalized.
///
/// SF Symbols vary wildly in aspect ratio and rendering mode: `person.3.fill` is nearly twice the
/// width of `numbersign.circle.fill`, and `flag.checkered.2.crossed` is a multicolor symbol that
/// ignores `foregroundStyle` and rendered black-and-white in a row of otherwise-green icons.
/// Forcing monochrome and a fixed square keeps every game row's title on the same left edge.
struct GameIcon: View {
    let systemName: String
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .symbolRenderingMode(.monochrome)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(RoundPlayColors.accent)
            .frame(width: size, height: size)
    }
}

struct GameCard: View {
    let metadata: GameMetadata

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GameIcon(systemName: metadata.iconName)
                .frame(width: 30, alignment: .center)
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
