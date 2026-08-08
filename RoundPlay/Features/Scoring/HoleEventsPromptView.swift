import SwiftUI
import RoundPlayEngine

/// Bingo Bango Bongo's three per-hole awards.
///
/// Rendered whenever any active game declares `.holeEvents`. Labels use plain English rather than
/// the game's jargon, because a first-time player has no idea what "bango" means.
struct HoleEventsPromptView: View {
    let players: [(id: UUID, name: String)]
    /// Current winner for each award, if recorded.
    let winners: [HoleEventKind: UUID]
    let onAward: (HoleEventKind, UUID) -> Void

    private func label(for kind: HoleEventKind) -> String {
        switch kind {
        case .bingo: "First on the green"
        case .bango: "Closest to the pin"
        case .bongo: "First in the hole"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(HoleEventKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label(for: kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(players, id: \.id) { player in
                            ChipButton(
                                title: player.name,
                                isSelected: winners[kind] == player.id
                            ) {
                                onAward(kind, player.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview("Light") {
    HoleEventsPromptView(
        players: [(UUID(), "Ann"), (UUID(), "Ben"), (UUID(), "Cal")],
        winners: [:]
    ) { _, _ in }
    .padding()
}

#Preview("Dark") {
    HoleEventsPromptView(
        players: [(UUID(), "Ann"), (UUID(), "Ben"), (UUID(), "Cal")],
        winners: [:]
    ) { _, _ in }
    .padding()
    .preferredColorScheme(.dark)
}
