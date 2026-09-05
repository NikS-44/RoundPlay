import SwiftUI

/// Par and handicap — two of the three facts a golfer checks on the tee. The hole number itself
/// is the nav-bar title now (tappable, to jump to another hole), so it no longer appears here.
/// Par sits on the left with no border — it's not tappable, and the border was confusing people
/// into thinking it was. Handicap mirrors it on the right at the same size.
struct HoleHeader: View {
    let par: Int
    let strokeIndex: Int
    /// The solo round's running score — "E", "THRU 3". Takes the middle of the board, where a
    /// group round shows its leader or Wolf line; the two never coexist, because a solo round has
    /// no leader to name and no Wolf to declare.
    var centerLine: (value: String, thru: Int)? = nil
    let leaderLine: String?
    let wolfLine: String?
    let onTapWolf: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Three equal-width columns, not two `Spacer()`s either side of the middle content.
            // "Handicap" is a much wider label than "Par", so a pair of equal spacers centers the
            // middle block between the *edges* of those two side blocks rather than in the row's
            // true center — which then sits visibly off from "Hole X" centered above it in the nav
            // bar. Three columns of exactly a third each can't drift with label width.
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    RoundPlayTypography.eyebrow("Par")
                        .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))
                    Text("\(par)")
                        .font(RoundPlayFont.archivo(36, .black))
                        .tracking(-1.8)
                        .foregroundStyle(RoundPlayColors.paperOnBoard)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                centerColumn
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .trailing, spacing: 2) {
                    RoundPlayTypography.eyebrow("Handicap")
                        .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.5))
                    Text("\(strokeIndex)")
                        .font(RoundPlayFont.archivo(36, .black))
                        .tracking(-1.8)
                        .foregroundStyle(RoundPlayColors.paperOnBoard)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundPlayColors.board)
    }

    @ViewBuilder
    private var centerColumn: some View {
        if let centerLine {
            // Exactly two lines, at exactly the sizes Par and Handicap use — "Thru 3" carries the
            // hole count in the label line rather than adding a third line under the score. A
            // taller centre column grew the whole board the moment the first score landed, which
            // shoved the scoring grid down the screen mid-round.
            VStack(spacing: 2) {
                RoundPlayTypography.eyebrow("Thru \(centerLine.thru)")
                    .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.55))
                    .contentTransition(.numericText())
                Text(centerLine.value)
                    .font(RoundPlayFont.archivo(36, .black))
                    .tracking(-1.8)
                    .foregroundStyle(RoundPlayColors.paperOnBoard)
                    .contentTransition(.numericText())
            }
        } else if let wolfLine {
            Button(action: onTapWolf) {
                HStack(spacing: 4) {
                    Text(wolfLine)
                        .font(RoundPlayFont.archivo(15, .semiBold))
                        .multilineTextAlignment(.center)
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))
                }
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.85))
                .frame(maxWidth: 130)
                .padding(.top, 8)
            }
            .buttonStyle(.plain)
        } else if let leaderLine {
            Text(leaderLine)
                .font(RoundPlayFont.archivo(15, .semiBold))
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 120)
                .padding(.top, 8)
        }
    }
}
