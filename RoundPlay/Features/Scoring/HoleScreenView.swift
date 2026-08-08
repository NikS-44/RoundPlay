import SwiftUI
import SwiftData
import RoundPlayEngine

/// One hole, one screen — the paper scorecard.
///
/// Prompts are driven entirely by the union of `requiredInputs` across the round's active games.
/// This view has no idea what Wolf or Bingo Bango Bongo *are*; it knows that some game needs a
/// partner choice, or three hole events, and renders accordingly.
struct HoleScreenView: View {
    @Environment(\.modelContext) private var modelContext

    let round: RoundRecord
    let course: Course

    @State private var hole: Int = 1

    private var state: RoundState {
        EngineBridge.roundState(for: round, course: course)
    }

    private var requiredInputs: Set<InputKind> {
        (round.games ?? []).reduce(into: Set<InputKind>()) { partial, game in
            guard let type = game.gameType else { return }
            partial.formUnion(GameLibrary.metadata(for: type).requiredInputs)
        }
    }

    /// Whoever is entering scores. Phase 1 is single-device, so this is always the first seat;
    /// Phase 2 replaces it with the signed-in account.
    private var scorekeeper: SeatRecord? { round.orderedSeats.first }

    var body: some View {
        VStack(spacing: 0) {
            HoleHeader(hole: hole, par: course.hole(hole)?.par ?? 4,
                       strokeIndex: course.hole(hole)?.strokeIndex ?? 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if requiredInputs.contains(.partnerChoice) { wolfPrompt }

                    ForEach(round.orderedSeats) { seat in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(seat.name).font(.headline)
                                if state.strokesReceived(hole: hole, player: seat.playerID) > 0 {
                                    Text("•")
                                        .foregroundStyle(RoundPlayColors.accent)
                                        .accessibilityLabel("Gets a stroke on this hole")
                                }
                                Spacer()
                            }
                            ScoreStripView(
                                par: course.hole(hole)?.par ?? 4,
                                selected: state.gross(hole: hole, player: seat.playerID)
                            ) { strokes in
                                record(strokes: strokes, for: seat)
                            }
                        }
                    }

                    if requiredInputs.contains(.holeEvents) { holeEventsPrompt }
                }
                .padding()
            }

            HoleNavigationBar(
                hole: $hole,
                isComplete: state.isComplete(hole: hole)
            )
        }
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var wolfPrompt: some View {
        let seats = round.orderedSeats
        if !seats.isEmpty {
            let wolfSeat = seats[(hole - 1) % seats.count]
            WolfPromptView(
                wolfName: wolfSeat.name,
                candidates: seats
                    .filter { $0.playerID != wolfSeat.playerID }
                    .map { (id: $0.playerID, name: $0.name) },
                declaration: state.wolfDeclaration(hole: hole)?.declaration
            ) { declaration in
                guard let scorekeeper else { return }
                try? EngineBridge.appendWolfDeclaration(
                    declaration, hole: hole, wolfID: wolfSeat.playerID, to: round,
                    enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
                    in: modelContext
                )
            }
        }
    }

    @ViewBuilder
    private var holeEventsPrompt: some View {
        let winners = HoleEventKind.allCases.reduce(into: [HoleEventKind: UUID]()) { partial, kind in
            partial[kind] = state.holeEventWinner(hole: hole, kind: kind)
        }
        HoleEventsPromptView(
            players: round.orderedSeats.map { (id: $0.playerID, name: $0.name) },
            winners: winners
        ) { kind, playerID in
            guard let scorekeeper else { return }
            try? EngineBridge.appendHoleEvent(
                kind, hole: hole, playerID: playerID, to: round,
                enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
                in: modelContext
            )
        }
    }

    private func record(strokes: Int, for seat: SeatRecord) {
        guard let scorekeeper else { return }
        try? EngineBridge.appendStrokes(
            strokes, hole: hole, playerID: seat.playerID, to: round,
            enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
            in: modelContext
        )
    }
}

/// Hole number, par, and stroke index — the three facts a golfer checks on the tee.
private struct HoleHeader: View {
    let hole: Int
    let par: Int
    let strokeIndex: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Hole \(hole)").font(.largeTitle.weight(.bold))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Par \(par)").font(.headline)
                Text("SI \(strokeIndex)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(RoundPlayColors.backgroundSecondaryGrouped)
    }
}

private struct HoleNavigationBar: View {
    @Binding var hole: Int
    let isComplete: Bool

    var body: some View {
        HStack {
            Button {
                hole = max(1, hole - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(hole == 1)

            Spacer()

            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isComplete
                                 ? RoundPlayColors.scoreUnderPar
                                 : RoundPlayColors.holePending)
                .accessibilityLabel(isComplete ? "Hole complete" : "Hole incomplete")

            Spacer()

            Button {
                hole = min(18, hole + 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(hole == 18)
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .padding(.horizontal)
        .background(RoundPlayColors.backgroundSecondaryGrouped)
    }
}

#Preview("Light") {
    NavigationStack {
        HoleScreenView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack {
        HoleScreenView(round: PreviewData.sampleRound, course: .previewCourse)
    }
    .modelContainer(PreviewData.container)
    .preferredColorScheme(.dark)
}
