import SwiftUI

/// The number strip for one player on one hole.
///
/// Centered on par rather than showing 1–12: a par 4 offers `3 4 5 6 7`, which covers the
/// overwhelming majority of real scores in five targets big enough to hit without looking.
/// Disasters go through "More", which is rare enough to deserve the extra tap.
struct ScoreStripView: View {
    let par: Int
    let selected: Int?
    let onSelect: (Int) -> Void

    @State private var isShowingOverflow = false

    /// Par − 1 through par + 3.
    private var range: [Int] {
        Array(max(1, par - 1)...(par + 3))
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(range, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Text("\(value)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(value == selected
                                      ? RoundPlayColors.accent
                                      : RoundPlayColors.fillSecondary)
                        )
                        .foregroundStyle(value == selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Score \(value)")
                .accessibilityAddTraits(value == selected ? [.isSelected] : [])
            }

            Button {
                isShowingOverflow = true
            } label: {
                Text("…")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(RoundPlayColors.fillTertiary)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More scores")
        }
        .confirmationDialog("Score", isPresented: $isShowingOverflow) {
            ForEach(1...15, id: \.self) { value in
                Button("\(value)") { onSelect(value) }
            }
        }
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
