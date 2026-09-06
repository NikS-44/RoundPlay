import SwiftUI
import RoundPlayEngine
import RoundPlayData

/// Where the round stands: everyone against par, then a block per game being played.
///
/// One scrolling page, not a pager. This used to nest its own `TabView(.verticalPage)` inside the
/// round's Hole/Stand/Card pager, and the inner one swallowed the vertical swipe — once you landed
/// here you could not page on to the scorecard. Nested vertical pagers have no way to agree on who
/// owns the gesture, so there is only one of them now.
struct WatchStandingsView: View {
    let round: RoundRecord
    let course: Course

    private var settlements: [Settlement] {
        EngineBridge.settlements(for: round, course: course)
    }

    private var state: RoundState {
        EngineBridge.roundState(for: round, course: course)
    }

    private var holes: ClosedRange<Int> { round.holeSegment.holeRange }

    /// Everyone's net score against the par of the holes they have actually played, best first.
    private var lines: [(name: String, versusPar: Int)] {
        round.orderedSeats.map { seat in
            let played = holes.filter { state.gross(hole: $0, player: seat.playerID) != nil }
            let net = played.reduce(0) { $0 + (state.net(hole: $1, player: seat.playerID) ?? 0) }
            let par = played.reduce(0) { $0 + (course.hole($1)?.par ?? 0) }
            return (seat.name, net - par)
        }
        .sorted { $0.versusPar < $1.versusPar }
    }

    private var holesPlayed: Int {
        holes.filter { hole in
            round.orderedSeats.contains { state.gross(hole: hole, player: $0.playerID) != nil }
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header("Stroke play", trailing: holesPlayed > 0 ? "Thru \(holesPlayed)" : nil)

                // A table, so it reads as one: names and numbers in two columns, separated by
                // hairlines. Every row used to sit in its own rounded container — the same
                // container the heading sat in — which made a standings table look like a menu of
                // buttons, and made the heading look like one of the players.
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if index > 0 { rowDivider }
                    HStack {
                        Text(line.name)
                            .font(.body)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(versusParLabel(line.versusPar))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(versusParColor(line.versusPar))
                    }
                    .padding(.vertical, 6)
                }

                ForEach(settlements, id: \.gameType) { settlement in
                    gameBlock(settlement)
                }
            }
            .padding(.horizontal, WatchLayout.leadingMargin)
            .padding(.bottom, 8)
        }
    }

    /// Section headings are set apart by weight and colour rather than by a container, so nothing
    /// on this screen looks tappable when none of it is.
    private func header(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 3)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 0.5)
    }

    @ViewBuilder
    private func gameBlock(_ settlement: Settlement) -> some View {
        let meta = GameLibrary.metadata(for: settlement.gameType)
        let leader = settlement.standings.max(by: { $0.money < $1.money })
        let why = settlement.holeExplanations.last?.text ?? ""

        header(meta.displayName)

        if let leader {
            HStack {
                Text(name(leader.playerID))
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(leader.money.formatted(.currency(code: "USD").sign(strategy: .always())))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(leader.money >= 0 ? WatchPalette.underPar : WatchPalette.overPar)
            }
            .padding(.vertical, 6)
        }

        if !why.isEmpty {
            Text(why)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
        }
    }

    private func name(_ id: UUID) -> String {
        round.orderedSeats.first { $0.playerID == id }?.name ?? "Unknown"
    }

    private func versusParLabel(_ value: Int) -> String {
        if value == 0 { return "E" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private func versusParColor(_ value: Int) -> Color {
        if value < 0 { return WatchPalette.underPar }
        if value > 0 { return WatchPalette.overPar }
        return .primary
    }
}
