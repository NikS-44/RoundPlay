import SwiftUI

/// The one leading margin every element on the hole screen lines up to.
enum WatchLayout {
    static let leadingMargin: CGFloat = 8

    /// How far the hole bar is lifted out of its toolbar slot to sit on the clock's line.
    ///
    /// watchOS places a leading toolbar item on its own row below the time. Nudging it up puts the
    /// hole number level with the clock, the way a navigation title sits — and the scores below are
    /// pulled up by the same amount, so the row the bar vacated isn't left as a band of black
    /// between the hole number and the first player.
    static let toolbarLift: CGFloat = 10
}

/// One player's score strip — the watch's version of the phone's `ScoreStripView`, and the reason
/// there is no "switch player" gesture to learn: every player is on screen at once, so choosing a
/// player is just scrolling to their row.
///
/// Horizontal inside a vertical list is a real tension on a small screen, which is why the chips
/// are wide enough that a drag across one is unambiguously sideways, and why the row's own label
/// sits above rather than beside it.
struct WatchScoreStrip: View {
    let par: Int
    /// Strokes this player gets on this hole. Sets where the strip opens and colours the pick.
    let strokesReceived: Int
    /// Where every player's strip on this hole opens when they have no score yet — the same value
    /// for the whole group, so the rows line up in one column instead of each drifting to its own
    /// net par. The phone does exactly this, for exactly this reason.
    let groupCenterScore: Int
    let selected: Int?
    let onSelect: (Int) -> Void

    /// Covers pick-ups and genuine blow-ups. Lazy, so the tail costs nothing.
    private let range = Array(1...20)

    /// What this player is expected to write down here — par plus whatever they're getting on this
    /// hole. Opening on raw par asked anyone with a shot to scroll on every hole they got one.
    private var expected: Int { par + strokesReceived }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 5) {
                    ForEach(range, id: \.self) { value in
                        chip(for: value)
                    }
                }
                // Same leading margin as the player name above it, so the first chip and the
                // name it belongs to share an edge instead of missing each other by a few points.
                .padding(.leading, WatchLayout.leadingMargin)
                .padding(.trailing, 8)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: 42)
            .sensoryFeedback(.selection, trigger: selected)
            .onAppear {
                proxy.scrollTo(selected ?? groupCenterScore, anchor: .center)
            }
        }
    }

    private func chip(for value: Int) -> some View {
        let isSelected = value == selected
        return Button {
            onSelect(value)
        } label: {
            Text("\(value)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? tint(for: value) : Color.white.opacity(0.13))
                )
                .overlay(alignment: .bottom) {
                    // Par is marked on the scale rather than written out above it. It was a line of
                    // its own for a while, sharing a row with the incomplete warning in a different
                    // colour — two unrelated facts crammed together. Par isn't something you read
                    // separately; it's the landmark you count from, so it belongs on the number.
                    // Same treatment the phone's score grid gives it.
                    if value == par && !isSelected {
                        Text("PAR")
                            .font(.system(size: 7, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(WatchPalette.accent)
                            .padding(.bottom, 3)
                    }
                }
                .overlay {
                    if value == par && !isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(WatchPalette.accent, lineWidth: 2)
                    }
                }
                .foregroundStyle(isSelected ? foreground(for: value) : Color.white)
        }
        .buttonStyle(.plain)
        .id(value)
        .accessibilityLabel("Score \(value)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Judged against *net* par, matching the phone: a 5 on a par 4 is a green net birdie for
    /// someone getting a shot here.
    private func tint(for value: Int) -> Color {
        if value < expected { return WatchPalette.underPar }
        if value > expected { return WatchPalette.overPar }
        return WatchPalette.accent
    }

    /// The under/over-par colours are light enough that white text disappears on them; the accent
    /// green is dark enough that black text does.
    private func foreground(for value: Int) -> Color {
        value == expected ? .white : .black
    }
}
