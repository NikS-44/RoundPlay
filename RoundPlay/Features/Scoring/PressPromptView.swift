import SwiftUI
import RoundPlayEngine
import RoundPlayData

/// The Nassau press, put to the group before they tee off.
///
/// A press is the one bet in a round that gets agreed *during* the round, so it is asked the way
/// it would be asked out loud — who's down, by how much, what the new bet costs, and what holes it
/// runs over. Both answers are recorded: passing is a decision the group may want to point at
/// later, and it is what stops the question following them down the fairway.
///
/// Deliberately not a blocker. Unlike the Wolf's declaration, which the real game will not let you
/// play past, a press can be ignored — so the scores sit right below it and stay tappable.
struct PressPromptView: View {
    let offer: NassauEngine.PressOffer
    /// Resolved by the caller; this view knows nothing about seats.
    let trailingName: String
    let leadingName: String
    let onDecide: (PressDecision) -> Void

    private var stakeLabel: String {
        offer.stake.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    private var holesLabel: String {
        offer.hole == offer.throughHole
            ? "hole \(offer.hole)"
            : "holes \(offer.hole)–\(offer.throughHole)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundPlayTypography.eyebrow("Press?")
                .foregroundStyle(RoundPlayColors.pin)

            RoundPlayTypography.headline(
                "\(trailingName) is \(offer.holesDown) down to \(leadingName) on the \(offer.segment.displayName)."
            )
            .fixedSize(horizontal: false, vertical: true)

            RoundPlayTypography.caption(
                "A press starts a second \(stakeLabel) bet over \(holesLabel). The original bet keeps running."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    onDecide(.accepted)
                } label: {
                    Text("Press")
                        .font(RoundPlayFont.archivo(16, .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(RoundPlayColors.paperOnBoard)
                        .background(
                            Capsule().fill(RoundPlayColors.accent)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onDecide(.declined)
                } label: {
                    Text("Not this time")
                        .font(RoundPlayFont.archivo(16, .semiBold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(RoundPlayColors.accent)
                        .background(
                            Capsule().strokeBorder(RoundPlayColors.accent.opacity(0.45), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .themedCard(cornerRadius: 16, fill: .secondaryBackground)
    }
}

#Preview("Two down") {
    PressPromptView(
        offer: NassauEngine.PressOffer(
            hole: 3,
            throughHole: 9,
            segment: .front,
            trailingPlayerID: UUID(),
            leadingPlayerID: UUID(),
            holesDown: 2,
            stake: 10
        ),
        trailingName: "Tilly",
        leadingName: "Nik",
        onDecide: { _ in }
    )
    .padding()
}
