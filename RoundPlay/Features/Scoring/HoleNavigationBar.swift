import SwiftUI

struct HoleNavigationBar: View {
    let hole: Int
    let holeRange: ClosedRange<Int>
    let isComplete: Bool
    let enteredCount: Int
    /// Seats needing a score, plus any required hole-event tallies (Bingo Bango Bongo's three
    /// winners) — not just the player count, when a game needs more than a stroke per hole.
    let totalCount: Int
    let isLastHole: Bool
    let isPostCompletionEdit: Bool
    let previousHoleIsIncomplete: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                // Always present, just invisible when complete — reserving the space keeps the
                // count text from sliding sideways as the icon appears and disappears.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isComplete ? 0 : 1)
                Text("\(enteredCount) of \(totalCount) entered")
                    .font(RoundPlayFont.archivo(18, .bold))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 10) {
                Button(action: onPrevious) {
                    Label("Previous Hole", systemImage: previousHoleIsIncomplete ? "exclamationmark.triangle.fill" : "chevron.left")
                        .font(RoundPlayFont.archivo(18, .bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(RoundPlayColors.accent)
                .disabled(hole == holeRange.lowerBound)

                if isLastHole {
                    Button(action: onFinish) {
                        Label(
                            isPostCompletionEdit ? "Done" : "Finish Round",
                            systemImage: isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                            .font(RoundPlayFont.archivo(20, .bold))
                            .labelStyle(.trailingIcon)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .roundPlayPrimaryButtonStyle()
                    .tint(RoundPlayColors.accent)
                } else {
                    // The warning is a small icon swap, not a color change — a fully orange
                    // button for "you haven't finished this hole yet" reads like an error state,
                    // when it's just an ordinary, expected part of entering scores.
                    Button(action: onNext) {
                        Label("Next Hole", systemImage: isComplete ? "chevron.right" : "exclamationmark.triangle.fill")
                            .font(RoundPlayFont.archivo(20, .bold))
                            .labelStyle(.trailingIcon)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .roundPlayPrimaryButtonStyle()
                    .tint(RoundPlayColors.accent)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(RoundPlayColors.backgroundSecondaryGrouped)
    }
}

/// Icon-after-title layout — "Next ›" reads more like forward motion than the default icon-first.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            // A fixed-width slot for the icon — chevron and warning-triangle glyphs aren't the
            // same width, so without this the whole label visibly shifts sideways every time
            // completeness flips and the icon swaps.
            configuration.icon
                .frame(width: 20)
        }
    }
}

private extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}
