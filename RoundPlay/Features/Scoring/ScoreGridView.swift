import SwiftUI

/// The score picker for a round with one seat — twelve cells filling the space three other players
/// used to occupy.
///
/// Fixed 1–11 rather than a range that slides with par: the numbers never move, so "5" is the
/// middle of row two on every hole of every course and the grid can be hit without being read.
/// Only the par outline moves. A par-centred range would keep every cell useful but would shift
/// every number hole to hole, and would push an albatross behind the overflow.
///
/// The carousel this replaces for solo rounds was never wrong about chip size — its problem was
/// that the number you wanted could be off screen. Nothing here scrolls.
struct ScoreGridView: View {
    let par: Int
    /// Strokes this player gets on this hole. Only used to judge the selected cell's color.
    var strokesReceived: Int = 0
    let selected: Int?
    let onSelect: (Int) -> Void

    /// Everything the grid shows directly. 11 covers a quintuple bogey on a par 5; anything worse
    /// goes through More, which is rare enough that a flick costs nothing.
    private static let range = Array(1...11)
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)

    @State private var isShowingOverflow = false
    /// The wheel's own value while the sheet is open. Starts past the grid's range, since a score
    /// inside it would have been one tap on the grid.
    @State private var overflowValue = 12

    private var netPar: Int { par + strokesReceived }

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 9) {
            ForEach(Self.range, id: \.self) { value in
                cell(for: value)
            }
            moreCell
        }
        .sensoryFeedback(RoundPlayHaptics.selection, trigger: selected)
        .sheet(isPresented: $isShowingOverflow) {
            overflowSheet
        }
    }

    private func cell(for value: Int) -> some View {
        let isSelected = value == selected
        let isPar = value == par
        return Button {
            onSelect(value)
        } label: {
            Text("\(value)")
                .font(RoundPlayFont.archivo(28, .bold))
                .frame(maxWidth: .infinity, minHeight: 62)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isSelected ? relativeToParColor(value) : RoundPlayColors.fillSecondary)
                )
                .overlay(alignment: .bottom) {
                    if isPar && !isSelected {
                        Text("PAR")
                            .font(RoundPlayFont.archivo(8, .bold))
                            .tracking(1)
                            .foregroundStyle(RoundPlayColors.accent)
                            .padding(.bottom, 5)
                    }
                }
                .overlay {
                    if isPar && !isSelected {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(RoundPlayColors.accent, lineWidth: 2.5)
                    }
                }
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Score \(value)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var moreCell: some View {
        Button {
            // Open past whatever is already recorded, so re-opening a 14 lands on 14.
            overflowValue = max(12, selected ?? 12)
            isShowingOverflow = true
        } label: {
            Text(selectedIsOffGrid ? "\(selected ?? 12)" : "More")
                .font(RoundPlayFont.archivo(selectedIsOffGrid ? 28 : 14, .bold))
                .frame(maxWidth: .infinity, minHeight: 62)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(selectedIsOffGrid
                              ? relativeToParColor(selected ?? 12)
                              : RoundPlayColors.fillTertiary)
                )
                .foregroundStyle(selectedIsOffGrid ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedIsOffGrid ? "Score \(selected ?? 12), change" : "More scores")
    }

    /// True when the recorded score is too high for the grid, so the More cell has to show it —
    /// otherwise a 14 would leave the whole grid looking as though nothing had been entered.
    private var selectedIsOffGrid: Bool {
        guard let selected else { return false }
        return !Self.range.contains(selected)
    }

    private var overflowSheet: some View {
        NavigationStack {
            VStack {
                Picker("Score", selection: $overflowValue) {
                    ForEach(12...30, id: \.self) { value in
                        Text("\(value)").font(RoundPlayFont.archivo(22, .bold)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            }
            .navigationTitle("Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isShowingOverflow = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSelect(overflowValue)
                        isShowingOverflow = false
                    }
                    .font(RoundPlayFont.archivo(17, .bold))
                }
            }
        }
        .presentationDetents([.height(280)])
    }

    /// Selected cells carry the same under/at/over-par color as the rest of the app, judged against
    /// *net* par — a 5 on a par 4 is a green net birdie for a player getting a stroke here.
    private func relativeToParColor(_ value: Int) -> Color {
        if value < netPar { return RoundPlayColors.scoreUnderPar }
        if value > netPar { return RoundPlayColors.scoreOverPar }
        return RoundPlayColors.accent
    }
}

#Preview("Par 4, nothing selected") {
    ScoreGridView(par: 4, selected: nil) { _ in }.padding()
}

#Preview("Par 4, bogey") {
    ScoreGridView(par: 4, selected: 5) { _ in }.padding()
}

#Preview("Par 3, off-grid score") {
    ScoreGridView(par: 3, selected: 14) { _ in }.padding()
}

#Preview("Dark") {
    ScoreGridView(par: 5, selected: 5) { _ in }
        .padding()
        .preferredColorScheme(.dark)
}
