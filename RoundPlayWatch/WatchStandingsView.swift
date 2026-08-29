import SwiftUI
import RoundPlayEngine
import RoundPlayData

struct WatchStandingsView: View {
    let round: RoundRecord
    let course: Course

    private var settlements: [Settlement] {
        EngineBridge.settlements(for: round, course: course)
    }

    var body: some View {
        TabView {
            if settlements.isEmpty {
                plainStrokePage
            }
            ForEach(settlements, id: \.gameType) { settlement in
                gamePage(settlement)
            }
        }
        .tabViewStyle(.verticalPage)
    }

    private var plainStrokePage: some View {
        let state = EngineBridge.roundState(for: round, course: course)
        let holes = round.holeSegment.holeRange
        let lines: [(name: String, rel: Int)] = round.orderedSeats.map { seat in
            let played = holes.filter { state.gross(hole: $0, player: seat.playerID) != nil }
            let net = played.reduce(0) { $0 + (state.net(hole: $1, player: seat.playerID) ?? 0) }
            let par = played.reduce(0) { $0 + (course.hole($1)?.par ?? 0) }
            return (seat.name, net - par)
        }.sorted { $0.rel < $1.rel }

        return List {
            Text("Stroke play")
                .font(.headline)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.name)
                    Spacer()
                    Text(relLabel(line.rel))
                        .foregroundStyle(line.rel < 0 ? WatchPalette.underPar : line.rel > 0 ? WatchPalette.overPar : .primary)
                }
            }
        }
    }

    private func gamePage(_ settlement: Settlement) -> some View {
        let leader = settlement.standings.max(by: { $0.money < $1.money })
        let why = settlement.holeExplanations.last?.text ?? ""
        return List {
            Text(GameLibrary.metadata(for: settlement.gameType).displayName)
                .font(.headline)
            if let leader {
                Text(name(leader.playerID))
                    .font(.title3)
                Text(leader.money.formatted(.currency(code: "USD").sign(strategy: .always())))
                    .foregroundStyle(leader.money >= 0 ? WatchPalette.underPar : WatchPalette.overPar)
            }
            if !why.isEmpty {
                Text(why)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func name(_ id: UUID) -> String {
        round.orderedSeats.first { $0.playerID == id }?.name ?? "Unknown"
    }

    private func relLabel(_ value: Int) -> String {
        if value == 0 { return "E" }
        return value > 0 ? "+\(value)" : "\(value)"
    }
}
