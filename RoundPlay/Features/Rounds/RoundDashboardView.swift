import SwiftUI
import SwiftData
import RoundPlayEngine

/// Live standings and money for every game in the round.
///
/// Every figure comes from `Settlement`. The dashboard performs no arithmetic of its own — if a
/// number is wrong here, the bug is in the engine and there is a failing fixture to write.
struct RoundDashboardView: View {
    let round: RoundRecord
    let course: Course

    private var settlements: [Settlement] {
        EngineBridge.settlements(for: round, course: course)
    }

    private func name(for playerID: UUID) -> String {
        round.orderedSeats.first { $0.playerID == playerID }?.name ?? "Unknown"
    }

    private struct PlainScoreLine: Identifiable {
        let seat: SeatRecord
        let holesPlayed: Int
        let gross: Int
        let net: Int
        let netRelativeToPar: Int
        var id: UUID { seat.id }
    }

    /// Plain stroke play, computed straight from the event log — used when no game is running,
    /// so a round with no side bets is still a normal scorecard, not a blank Standings tab.
    private var plainScoreLines: [PlainScoreLine] {
        let state = EngineBridge.roundState(for: round, course: course)
        let holes = round.holeSegment.holeRange
        return round.orderedSeats.map { seat in
            let played = holes.filter { state.gross(hole: $0, player: seat.playerID) != nil }
            let gross = played.reduce(0) { $0 + (state.gross(hole: $1, player: seat.playerID) ?? 0) }
            let net = played.reduce(0) { $0 + (state.net(hole: $1, player: seat.playerID) ?? 0) }
            let par = played.reduce(0) { $0 + (course.hole($1)?.par ?? 0) }
            return PlainScoreLine(seat: seat, holesPlayed: played.count, gross: gross, net: net, netRelativeToPar: net - par)
        }
        .sorted { $0.net < $1.net }
    }

    private func relativeToParLabel(_ value: Int) -> String {
        if value == 0 { return "E" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    var body: some View {
        RoundPlayList.plain {
            if settlements.isEmpty {
                Section {
                    ForEach(Array(plainScoreLines.enumerated()), id: \.element.id) { index, line in
                        HStack(spacing: 12) {
                            RoundPlayTypography.numeral("\(index + 1)", size: 15)
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .leading)
                            RoundPlayTypography.headline(line.seat.name)
                            Spacer()
                            if line.holesPlayed > 0 {
                                Text("Gross \(line.gross)")
                                    .font(RoundPlayFont.archivo(12))
                                    .foregroundStyle(.secondary)
                                RoundPlayTypography.money(relativeToParLabel(line.netRelativeToPar), size: 15)
                                    .foregroundStyle(
                                        line.netRelativeToPar < 0 ? RoundPlayColors.scoreUnderPar
                                            : line.netRelativeToPar > 0 ? RoundPlayColors.scoreOverPar
                                            : RoundPlayColors.scoreAtPar
                                    )
                                    .frame(minWidth: 40, alignment: .trailing)
                            } else {
                                Text("No scores yet")
                                    .font(RoundPlayFont.archivo(12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .roundPlayListRowSeparatorFullWidth()
                    }
                } header: {
                    RoundPlaySectionHeader("Scoring")
                } footer: {
                    RoundPlayTypography.caption("No games running — plain stroke play, net score vs. par.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(settlements, id: \.gameType) { settlement in
                Section {
                    ForEach(Array(sortedStandings(for: settlement).enumerated()), id: \.element.id) { index, standing in
                        HStack(spacing: 12) {
                            RoundPlayTypography.numeral("\(index + 1)", size: 15)
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .leading)
                            RoundPlayTypography.headline(name(for: standing.playerID))
                            Spacer()
                            Text(scoreLabel(for: settlement.gameType, points: standing.points))
                                .font(RoundPlayFont.archivo(12))
                                .foregroundStyle(.secondary)
                            RoundPlayTypography.money(
                                standing.money.formatted(.currency(code: "USD").sign(strategy: .always())),
                                size: 15
                            )
                            .foregroundStyle(moneyColor(standing.money))
                            .frame(minWidth: 76, alignment: .trailing)
                        }
                        .roundPlayListRowSeparatorFullWidth()
                    }

                    if !settlement.holeExplanations.isEmpty {
                        DisclosureGroup("Hole by hole") {
                            // Indexed rather than keyed on `text`: Nassau emits two explanations
                            // for one hole (the result, then a press opening), and identical
                            // strings across holes are common ("Hole 4: halved.").
                            ForEach(Array(settlement.holeExplanations.enumerated()), id: \.offset) { _, explanation in
                                RoundPlayTypography.caption(explanation.text)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    RoundPlaySectionHeader(GameLibrary.metadata(for: settlement.gameType).displayName)
                }
            }

            if settlements.contains(where: { $0.gameType != .strokePlay }) {
                Section { SettleUpSection(round: round, course: course) }
            }
        }
        .navigationTitle("Standings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { AuditLogView(round: round) } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private func moneyColor(_ amount: Decimal) -> Color {
        if amount > 0 { return RoundPlayColors.moneyPositive }
        if amount < 0 { return RoundPlayColors.moneyNegative }
        return RoundPlayColors.moneyEven
    }

    private func sortedStandings(for settlement: Settlement) -> [PlayerStanding] {
        settlement.gameType == .strokePlay
            ? settlement.standings.sorted { $0.points < $1.points }
            : settlement.standings.sorted { $0.money > $1.money }
    }

    private func scoreLabel(for game: GameType, points: Int) -> String {
        game == .strokePlay ? "\(points) strokes" : "\(points) pts"
    }
}

/// Opens the who-owes-who breakdown.
///
/// This shipped for a long time as a disabled "Coming soon" stub, from before `SettleUpSheet`
/// existed. Once the Summary tab grew a working Settle Up button, the stub was actively lying:
/// the same round offered a live breakdown on one tab and a greyed-out promise on the next.
///
/// The "never holds or moves money" line stays — that's a standing disclosure, not a stub.
private struct SettleUpSection: View {
    let round: RoundRecord
    let course: Course

    @State private var isSettling = false

    var body: some View {
        VStack(spacing: 6) {
            Button("Settle Up") { isSettling = true }
                .roundPlayPrimaryButtonStyle()
                .tint(RoundPlayColors.accent)
            RoundPlayTypography.eyebrow("RoundPlay never holds or moves money")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .sheet(isPresented: $isSettling) {
            SettleUpSheet(round: round, course: course)
        }
    }
}

#Preview("Light") {
    NavigationStack {
        RoundDashboardView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack {
        RoundDashboardView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
    .preferredColorScheme(.dark)
}
