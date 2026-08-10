import SwiftUI

/// The number strip for one player on one hole — a horizontally scrolling carousel that *is* the
/// picker. No overflow sheet: an albatross on a par 5 or a men's-tee disaster are both just a
/// swipe away, not a separate "…" button and a second screen.
struct ScoreStripView: View {
    let par: Int
    /// Strokes this player gets on this hole from their course handicap — 0 most holes, 1 (rarely
    /// 2) on the holes it's allocated to. Only used to judge *this chip's* color once picked.
    var strokesReceived: Int = 0
    /// Where every player's carousel on this hole opens scrolled to — the same value for the
    /// whole group (par adjusted by the group's average handicap stroke, not this player's own),
    /// so every row lines up in the same column instead of each drifting to its own net par.
    var groupCenterScore: Int? = nil
    let selected: Int?
    let onSelect: (Int) -> Void

    /// Covers normal play, pick-ups, and unusually high but valid hole scores. `LazyHStack`
    /// keeps this cheap even though every strip on the hole renders its own copy.
    private let range = Array(1...20)

    /// Net par for *this* player on *this* hole — par 4 is still a 5 to make net par if they're
    /// getting a stroke here. Used only to color the selected chip, not to position the carousel.
    private var netPar: Int { par + strokesReceived }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(range, id: \.self) { value in
                        chip(for: value)
                    }
                }
                .padding(.horizontal, 4)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: 52)
            // The most-repeated interaction in the app — a score landing should feel like it
            // landed, not like a silent state change somewhere off screen.
            .sensoryFeedback(RoundPlayHaptics.selection, trigger: selected)
            .onAppear {
                // Land on today's score if there is one, otherwise the group's shared expected
                // score — every player's carousel opens at the same position so they line up
                // column by column, instead of each drifting to its own net par.
                proxy.scrollTo(selected ?? groupCenterScore ?? par, anchor: .center)
            }
        }
    }

    private func chip(for value: Int) -> some View {
        let isSelected = value == selected
        return Button {
            onSelect(value)
        } label: {
            Text("\(value)")
                .font(RoundPlayFont.archivo(21, .bold))
                .frame(minWidth: 46, minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? relativeToParColor(value) : RoundPlayColors.fillSecondary)
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .id(value)
        .accessibilityLabel("Score \(value)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Selected chips carry the same under/at/over-par color the rest of the app already uses
    /// for scores, so scanning a row of players' carousels reads like a scorecard, not a dial pad.
    /// Judged against *net* par, not raw par — a 5 on a par 4 is a green net-birdie for a player
    /// getting a stroke here, the same as it would be for anyone else shooting net 3 on a par 4.
    private func relativeToParColor(_ value: Int) -> Color {
        if value < netPar { return RoundPlayColors.scoreUnderPar }
        if value > netPar { return RoundPlayColors.scoreOverPar }
        return RoundPlayColors.accent
    }
}

#Preview("Par 4, nothing selected") {
    ScoreStripView(par: 4, selected: nil) { _ in }.padding()
}

#Preview("Par 3, five selected") {
    ScoreStripView(par: 3, selected: 5) { _ in }.padding()
}

#Preview("Dark") {
    ScoreStripView(par: 5, selected: 5) { _ in }
        .padding()
        .preferredColorScheme(.dark)
}
