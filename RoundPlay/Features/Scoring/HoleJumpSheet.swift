import SwiftUI

/// Jump straight to any hole — tapping the hole number is faster than eighteen taps of Next.
struct HoleJumpSheet: View {
    @Binding var hole: Int
    let holeRange: ClosedRange<Int>
    let incompleteHoles: Set<Int>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Picker("Hole", selection: $hole) {
                ForEach(Array(holeRange), id: \.self) { value in
                    Label {
                        Text("Hole \(value)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(RoundPlayColors.scoreOverPar)
                            .opacity(incompleteHoles.contains(value) ? 1 : 0)
                    }
                    .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle("Jump to Hole")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A red banner telling the scorekeeper exactly why Finish Round didn't work.
struct IncompleteHoleBanner: View {
    /// Bingo Bango Bongo's three tallies count toward completeness too, so on those rounds "missing
    /// a score" is only half the story and sends the scorekeeper hunting for a score that's
    /// already there.
    let needsHoleEvents: Bool

    private var message: String {
        needsHoleEvents
            ? "This hole isn't finished. Every player needs a score, and each tally needs a winner."
            : "This hole is missing a score. Enter every player before finishing."
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(RoundPlayFont.archivo(13, .semiBold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundPlayColors.scoreOverPar)
    }
}
