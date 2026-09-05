import SwiftUI
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// The word the fireworks land on when there is no money in the round.
enum SoloCompletion {
    static func word(versusPar: Int) -> String {
        switch versusPar {
        case ..<0: "FIRED"
        case 0: "LEVEL"
        case 1...9: "SOLID"
        default: "WRAPPED"
        }
    }
}

/// The landing screen for a finished solo round.
///
/// A group round ends on who owes who. A solo round ends on the only three questions left: what did
/// you shoot, what did the round look like, and was it any good compared to the last time.
struct SoloSummaryView: View {
    @Environment(\.modelContext) private var modelContext

    let round: RoundRecord
    let course: Course
    let onShare: () -> Void
    let onShowScorecard: () -> Void

    private var seat: SeatRecord? { round.orderedSeats.first }
    private var state: RoundState { EngineBridge.roundState(for: round, course: course) }
    private var holes: ClosedRange<Int> { round.holeSegment.holeRange }

    private var holesPlayed: Int {
        guard let seat else { return 0 }
        return RelativeToPar.holesPlayed(state: state, playerID: seat.playerID, holes: holes)
    }

    private var gross: Int {
        guard let seat else { return 0 }
        return holes.reduce(0) { $0 + (state.gross(hole: $1, player: seat.playerID) ?? 0) }
    }

    private var versusPar: Int {
        guard let seat else { return 0 }
        return RelativeToPar.grossVersusPar(state: state, course: course, playerID: seat.playerID, holes: holes)
    }

    /// The board-tuned variants, not the standard light/dark-adaptive `scoreUnderPar`/
    /// `scoreOverPar` — those are tuned against a system background, and this sits on the same
    /// near-black board `RoundSummaryView`'s money figure already uses these colors against.
    private var relativeToParColor: Color {
        if versusPar < 0 { return RoundPlayColors.moneyPositiveOnBoard }
        if versusPar > 0 { return RoundPlayColors.moneyNegativeOnBoard }
        return RoundPlayColors.paperOnBoard
    }

    private var shape: RoundShape {
        guard let seat else { return RoundShape() }
        return RoundShape.of(state: state, course: course, playerID: seat.playerID, holes: holes)
    }

    private var historyLine: String? {
        guard let seat else { return nil }
        return SoloRoundHistory.line(for: round, course: course, playerID: seat.playerID, in: modelContext)
    }

    private var isPartial: Bool { holesPlayed < holes.count }

    var body: some View {
        RoundPlayList.plain {
            heroCard

            Section {
                HStack(spacing: 12) {
                    SummaryActionButton(title: "Share", systemImage: "square.and.arrow.up", isFilled: true, action: onShare)
                }
            }
            .listRowSeparator(.hidden)

            if !shape.counts.isEmpty {
                Section {
                    ForEach(shape.counts, id: \.label) { row in
                        HStack {
                            RoundPlayTypography.headline(row.label)
                            Spacer()
                            RoundPlayTypography.numeral("\(row.count)", size: 17)
                        }
                        .roundPlayListRowSeparatorFullWidth()
                    }

                    if let best = shape.best {
                        holeRow(title: "Best hole", result: best)
                    }
                    if let worst = shape.worst, worst.hole != shape.best?.hole {
                        holeRow(title: "Worst hole", result: worst)
                    }
                } header: {
                    RoundPlaySectionHeader("The Round")
                } footer: {
                    if isPartial {
                        RoundPlayTypography.caption("This round ended early. Totals cover the holes that were scored.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(action: onShowScorecard) {
                    HubRow(
                        icon: "square.grid.3x3",
                        title: "Scorecard",
                        subtitle: "Every hole, gross and net",
                        showsChevron: true
                    )
                }
                .buttonStyle(RoundPlayRowButtonStyle())
                .roundPlayListRowSeparatorFullWidth()
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func holeRow(title: String, result: RoundShape.HoleResult) -> some View {
        HStack {
            RoundPlayTypography.headline(title)
            Spacer()
            RoundPlayTypography.caption("Hole \(result.hole)")
                .foregroundStyle(.secondary)
            RoundPlayTypography.money(RelativeToPar.label(result.versusPar), size: 15)
                .foregroundStyle(
                    result.versusPar < 0 ? RoundPlayColors.scoreUnderPar
                        : result.versusPar > 0 ? RoundPlayColors.scoreOverPar
                        : RoundPlayColors.scoreAtPar
                )
                .frame(minWidth: 38, alignment: .trailing)
        }
        .roundPlayListRowSeparatorFullWidth()
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundPlayTypography.eyebrow("Round Complete")
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.65))
            RoundPlayTypography.title(round.courseName)
                .foregroundStyle(RoundPlayColors.paperOnBoard)
            Text(isPartial
                 ? "\(holesPlayed) holes · \(round.startedAt.formatted(date: .abbreviated, time: .omitted))"
                 : round.startedAt.formatted(date: .abbreviated, time: .omitted))
                .font(RoundPlayFont.archivo(13))
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))

            Divider().overlay(RoundPlayColors.paperOnBoard.opacity(0.15))

            // Gross, labeled, on the left — the same eyebrow-then-big-number pattern the hole
            // header already uses for Par and Handicap. Relative-to-par stands alone on the
            // right at the same size and needs no label: "+4" reads as a score on sight the way
            // every golf leaderboard shows it, the way a bare "40" would not.
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    RoundPlayTypography.eyebrow("Gross")
                        .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.55))
                    Text("\(gross)")
                        .font(RoundPlayFont.archivo(46, .black))
                        .tracking(-2)
                        .foregroundStyle(RoundPlayColors.paperOnBoard)
                }
                Spacer()
                Text(RelativeToPar.label(versusPar))
                    .font(RoundPlayFont.archivo(46, .black))
                    .tracking(-2)
                    .foregroundStyle(relativeToParColor)
            }

            if let historyLine {
                Text(historyLine)
                    .font(RoundPlayFont.archivo(14, .semiBold))
                    .foregroundStyle(RoundPlayColors.pin)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .boardCard(cornerRadius: 20)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}
