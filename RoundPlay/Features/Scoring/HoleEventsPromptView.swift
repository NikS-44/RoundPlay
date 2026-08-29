import SwiftUI
import RoundPlayEngine
import RoundPlayData

/// Bingo Bango Bongo's three per-hole awards.
///
/// Rendered whenever any active game declares `.holeEvents`. Labels use plain English rather than
/// the game's jargon, because a first-time player has no idea what "bango" means.
struct HoleEventsPromptView: View {
    let players: [(id: UUID, name: String)]
    /// Current winner for each award, if recorded.
    let winners: [HoleEventKind: UUID]
    let onAward: (HoleEventKind, UUID) -> Void
    var onClear: ((HoleEventKind) -> Void)? = nil

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
                    HStack {
                        RoundPlayTypography.eyebrow(label(for: kind))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if winners[kind] != nil, let onClear {
                            Button("Clear") { onClear(kind) }
                                .font(RoundPlayFont.archivo(12, .semiBold))
                                .foregroundStyle(RoundPlayColors.scoreOverPar)
                        }
                    }

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
