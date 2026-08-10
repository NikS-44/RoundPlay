import SwiftUI
import RoundPlayEngine

/// The landing screen for a finished round — a themed summary card, not another spreadsheet.
/// Money at a glance, one tap to share or settle up, and links out to the full scorecard and
/// standings for anyone who wants the detail.
struct RoundSummaryView: View {
    let round: RoundRecord
    let course: Course
    let onShare: () -> Void
    let onSettleUp: () -> Void
    let onShowScorecard: () -> Void
    let onShowStandings: () -> Void

    private var settlements: [Settlement] {
        EngineBridge.settlements(for: round, course: course)
    }

    private var moneySettlements: [Settlement] { settlements.filter { $0.gameType != .strokePlay } }
    private var hasGames: Bool { !moneySettlements.isEmpty }

    private var gameNames: String {
        (round.games ?? [])
            .compactMap { $0.gameType.map { GameLibrary.metadata(for: $0).displayName } }
            .joined(separator: ", ")
    }

    /// Every player's total across every game this round, biggest winner first — the same
    /// number `RoundShareContent` sums to build the "who owes who" text.
    private var netStandings: [(seat: SeatRecord, net: Decimal)] {
        var totals: [UUID: Decimal] = [:]
        for settlement in moneySettlements {
            for standing in settlement.standings {
                totals[standing.playerID, default: 0] += standing.money
            }
        }
        return round.orderedSeats
            .map { ($0, totals[$0.playerID] ?? 0) }
            .sorted { $0.1 > $1.1 }
    }

    /// Gross and net strokes for the round, shown regardless of whether any money games ran.
    ///
    /// Every total is computed over only the holes this player actually has a score for. Summing
    /// par across the *whole* segment while gross only covered played holes made a round finished
    /// after 4 holes report "Gross 22 · −49", which reads as a course record rather than a short
    /// round.
    private var finalScores: [(seat: SeatRecord, gross: Int, netRelativeToPar: Int, holesPlayed: Int)] {
        let state = EngineBridge.roundState(for: round, course: course)
        let holes = round.holeSegment.holeRange
        return round.orderedSeats.map { seat in
            let played = holes.filter { state.gross(hole: $0, player: seat.playerID) != nil }
            let gross = played.reduce(0) { $0 + (state.gross(hole: $1, player: seat.playerID) ?? 0) }
            let net = played.reduce(0) { $0 + (state.net(hole: $1, player: seat.playerID) ?? 0) }
            let par = played.reduce(0) { $0 + (course.hole($1)?.par ?? 0) }
            return (seat, gross, net - par, played.count)
        }
        .sorted { $0.netRelativeToPar < $1.netRelativeToPar }
    }

    /// True when the round stopped short of its full segment — the score rows then say how far
    /// the group actually got, so "Gross 22" has somewhere to stand.
    private var isPartialRound: Bool {
        finalScores.contains { $0.holesPlayed < round.holeSegment.holeRange.count }
    }

    var body: some View {
        RoundPlayList.plain {
            heroCard

            Section {
                actionButtons
            }
            .listRowSeparator(.hidden)

            Section {
                ForEach(Array(finalScores.enumerated()), id: \.element.seat.id) { index, entry in
                    finalScoreRow(
                        rank: index + 1,
                        seat: entry.seat,
                        gross: entry.gross,
                        netRelativeToPar: entry.netRelativeToPar,
                        holesPlayed: entry.holesPlayed
                    )
                }
            } header: {
                RoundPlaySectionHeader("Final Scores")
            } footer: {
                if isPartialRound {
                    RoundPlayTypography.caption("This round ended early — totals cover the holes that were scored.")
                        .foregroundStyle(.secondary)
                }
            }

            if hasGames {
                Section {
                    ForEach(Array(netStandings.enumerated()), id: \.element.seat.id) { index, entry in
                        moneyRow(rank: index + 1, seat: entry.seat, net: entry.net)
                    }
                } header: {
                    RoundPlaySectionHeader(gameNames)
                }
            }

            Section {
                Button {
                    onShowScorecard()
                } label: {
                    HubRow(
                        icon: "square.grid.3x3",
                        title: "Scorecard",
                        subtitle: "Every hole, every player",
                        showsChevron: true
                    )
                }
                .buttonStyle(RoundPlayRowButtonStyle())
                .roundPlayListRowSeparatorFullWidth()

                Button {
                    onShowStandings()
                } label: {
                    HubRow(
                        icon: "chart.bar",
                        title: "Standings",
                        subtitle: hasGames ? "Hole-by-hole breakdown" : "No games this round",
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

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundPlayTypography.eyebrow("Round Complete")
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.65))
            RoundPlayTypography.title(round.courseName)
                .foregroundStyle(RoundPlayColors.paperOnBoard)
            Text("\(pluralized(round.orderedSeats.count, "player")) · \(round.startedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(RoundPlayFont.archivo(13))
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))

            if let leader = netStandings.first, leader.net > 0 {
                Divider().overlay(RoundPlayColors.paperOnBoard.opacity(0.15))
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(RoundPlayColors.pin)
                    Text("\(leader.seat.name) came out ahead")
                        .font(RoundPlayFont.archivo(14, .semiBold))
                        .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.9))
                    Spacer()
                    RoundPlayTypography.money(leader.net.formatted(.currency(code: "USD").sign(strategy: .always())))
                        .foregroundStyle(RoundPlayColors.moneyPositiveOnBoard)
                }
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

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            SummaryActionButton(title: "Share", systemImage: "square.and.arrow.up", isFilled: true, action: onShare)
            if hasGames {
                SummaryActionButton(title: "Settle Up", systemImage: "dollarsign.circle", isFilled: false, action: onSettleUp)
            }
        }
    }

    // MARK: - Money rows

    private func moneyRow(rank: Int, seat: SeatRecord, net: Decimal) -> some View {
        HStack(spacing: 12) {
            RoundPlayTypography.numeral("\(rank)", size: 15)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            RoundPlayTypography.headline(seat.name)
            Spacer()
            RoundPlayTypography.money(net.formatted(.currency(code: "USD").sign(strategy: .always())))
                .foregroundStyle(moneyColor(net))
        }
        .roundPlayListRowSeparatorFullWidth()
    }

    private func moneyColor(_ amount: Decimal) -> Color {
        if amount > 0 { return RoundPlayColors.moneyPositive }
        if amount < 0 { return RoundPlayColors.moneyNegative }
        return RoundPlayColors.moneyEven
    }

    // MARK: - Final score rows

    private func finalScoreRow(rank: Int, seat: SeatRecord, gross: Int, netRelativeToPar: Int, holesPlayed: Int) -> some View {
        HStack(spacing: 12) {
            RoundPlayTypography.numeral("\(rank)", size: 15)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            RoundPlayTypography.headline(seat.name)
            Spacer()
            Text(isPartialRound ? "Gross \(gross) · thru \(holesPlayed)" : "Gross \(gross)")
                .font(RoundPlayFont.archivo(12))
                .foregroundStyle(.secondary)
            RoundPlayTypography.money(relativeToParLabel(netRelativeToPar), size: 15)
                .foregroundStyle(scoreColor(netRelativeToPar))
                .frame(minWidth: 40, alignment: .trailing)
        }
        .roundPlayListRowSeparatorFullWidth()
    }

    private func relativeToParLabel(_ value: Int) -> String {
        if value == 0 { return "E" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private func scoreColor(_ relativeToPar: Int) -> Color {
        if relativeToPar < 0 { return RoundPlayColors.scoreUnderPar }
        if relativeToPar > 0 { return RoundPlayColors.scoreOverPar }
        return RoundPlayColors.scoreAtPar
    }
}

/// A capsule CTA sized to sit next to its sibling — "Share" filled solid, "Settle Up" a crisp
/// outline instead of the system `.bordered` style's washed-out translucent fill, so the pair
/// reads as one deliberate two-button group instead of two mismatched controls.
private struct SummaryActionButton: View {
    let title: String
    let systemImage: String
    let isFilled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Baseline-aligned, not centre-aligned. `square.and.arrow.up` has an arrow poking out
            // above the tray, so its bounding box carries far more empty space above the visible
            // glyph than below — centring the box drops the part you actually see below the
            // text's optical centre. Sitting both on the same baseline is what SF Symbols are
            // drawn for, and it holds for the round `dollarsign.circle` on the sibling button too.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Built from Image + Text instead of `Label` — the SF Symbol inside a `Label`
                // scales off the archivo font's metrics, which rendered it noticeably oversized
                // next to the text; sizing the icon on its own keeps it proportionate.
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(RoundPlayFont.archivo(16, .semiBold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isFilled ? Color.white : RoundPlayColors.accent)
            .background(
                Capsule().fill(isFilled ? RoundPlayColors.accent : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(RoundPlayColors.accent, lineWidth: isFilled ? 0 : 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Light") {
    NavigationStack {
        RoundSummaryView(
            round: PreviewData.sampleRound,
            course: .previewCourse,
            onShare: {}, onSettleUp: {}, onShowScorecard: {}, onShowStandings: {}
        )
    }
    .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack {
        RoundSummaryView(
            round: PreviewData.sampleRound,
            course: .previewCourse,
            onShare: {}, onSettleUp: {}, onShowScorecard: {}, onShowStandings: {}
        )
    }
    .modelContainer(PreviewData.container)
    .preferredColorScheme(.dark)
}
