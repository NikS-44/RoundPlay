import SwiftUI

/// Par and handicap — two of the three facts a golfer checks on the tee. The hole number itself
/// is the nav-bar title now (tappable, to jump to another hole), so it no longer appears here.
/// Par sits on the left with no border — it's not tappable, and the border was confusing people
/// into thinking it was. Handicap mirrors it on the right at the same size.
struct HoleHeader: View {
    let par: Int
    let strokeIndex: Int
    let leaderLine: String?
    let wolfLine: String?
    let onTapWolf: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    RoundPlayTypography.eyebrow("Par")
                        .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))
                    Text("\(par)")
                        .font(RoundPlayFont.archivo(36, .black))
                        .tracking(-1.8)
                        .foregroundStyle(RoundPlayColors.paperOnBoard)
                        .contentTransition(.numericText())
                }

                Spacer()

                if let wolfLine {
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
                    Spacer()
                } else if let leaderLine {
                    Text(leaderLine)
                        .font(RoundPlayFont.archivo(15, .semiBold))
                        .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 120)
                        .padding(.top, 8)
                    Spacer()
                }

                VStack(alignment: .trailing, spacing: 2) {
                    RoundPlayTypography.eyebrow("Handicap")
                        .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.5))
                    Text("\(strokeIndex)")
                        .font(RoundPlayFont.archivo(36, .black))
                        .tracking(-1.8)
                        .foregroundStyle(RoundPlayColors.paperOnBoard)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundPlayColors.board)
    }
}
