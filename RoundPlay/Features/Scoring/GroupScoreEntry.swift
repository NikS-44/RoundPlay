import SwiftUI
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// Score entry for a round with more than one seat: a labelled carousel per player, plus whatever
/// declarations the round's games require before or alongside the scores.
///
/// This view has no idea what Wolf or Bingo Bango Bongo *are* — it knows some game needs a partner
/// choice, or three hole-event winners, and renders accordingly.
struct GroupScoreEntry: View {
    @Environment(\.modelContext) private var modelContext

    let round: RoundRecord
    let course: Course
    let hole: Int
    let state: RoundState
    let requiredInputs: Set<InputKind>
    let isPostCompletionEdit: Bool
    let groupCenterScore: Int
    let onRecord: (Int, SeatRecord) -> Void
    let onClear: (SeatRecord) -> Void

    /// Whoever is entering scores. Phase 1 is single-device, so this is always the first seat;
    /// Phase 2 replaces it with the signed-in account.
    private var scorekeeper: SeatRecord? { round.orderedSeats.first }

    private var wolfDeclarationPending: Bool {
        requiredInputs.contains(.partnerChoice) && state.wolfDeclaration(hole: hole) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Above the scores because it is a question about the hole nobody has played yet, and
            // because money agreed after the fact isn't agreed at all. It does not gate the strips
            // the way the Wolf's declaration does — a group that would rather just play on can
            // score straight through it.
            if let pressOffer { pressPrompt(pressOffer) }

            // Wolf declares before anyone's tee shot is scored — showing the score strips first
            // would let the group enter scores while the Wolf is still deciding whether to go it
            // alone, which the real game never allows. Once declared, the choice moves up into the
            // header and this prompt gets out of the way.
            if wolfDeclarationPending {
                wolfPrompt
            } else {
                ForEach(round.orderedSeats) { seat in
                    seatRow(seat)
                }

                if requiredInputs.contains(.holeEvents) { holeEventsPrompt }
            }
        }
    }

    private func seatRow(_ seat: SeatRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RoundPlayTypography.headline(seat.name)
                // Best Ball's team is fixed for the round; Sixes' partner changes every six holes,
                // so it's looked up per hole instead.
                if let team = round.bestBallTeamLabel(for: seat) ?? round.sixesTeamLabel(for: seat, atHole: hole) {
                    TeamBadge(team: team)
                }
                if state.strokesReceived(hole: hole, player: seat.playerID) > 0 {
                    RoundPlayTypography.eyebrow("+1 stroke")
                        .foregroundStyle(RoundPlayColors.accent)
                }
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 8) {
                ScoreStripView(
                    par: course.hole(hole)?.par ?? 4,
                    strokesReceived: state.strokesReceived(hole: hole, player: seat.playerID),
                    groupCenterScore: groupCenterScore,
                    selected: state.gross(hole: hole, player: seat.playerID)
                ) { strokes in
                    onRecord(strokes, seat)
                }
                // Rebuild per hole so the carousel re-centers on the new hole's expected score.
                // Without this the view identity is just the seat, so `onAppear` never fires
                // again and hole 2 opens still scrolled to wherever hole 1 was left.
                .id(hole)
                if isPostCompletionEdit, state.gross(hole: hole, player: seat.playerID) != nil {
                    Button("Clear") { onClear(seat) }
                        .font(RoundPlayFont.archivo(12, .semiBold))
                        .foregroundStyle(RoundPlayColors.scoreOverPar)
                }
            }
        }
    }

    private var wolfPrompt: some View {
        WolfDeclarationPrompt(round: round, hole: hole, state: state)
    }

    /// The press question, but only on the hole the press would start on.
    ///
    /// Recomputed from the round rather than held in `@State`: correcting a score back on hole 2
    /// has to be able to take the question on hole 3 away again.
    private var pressOffer: NassauEngine.PressOffer? {
        // Re-opening a finished round to fix a score is not the moment to be offered a new bet.
        guard !isPostCompletionEdit else { return nil }
        guard let offer = EngineBridge.nassauPressOffer(for: round, course: course),
              offer.hole == hole else { return nil }
        return offer
    }

    @ViewBuilder
    private func pressPrompt(_ offer: NassauEngine.PressOffer) -> some View {
        let names = round.orderedSeats.reduce(into: [UUID: String]()) { $0[$1.playerID] = $1.name }
        PressPromptView(
            offer: offer,
            trailingName: names[offer.trailingPlayerID] ?? "They",
            leadingName: names[offer.leadingPlayerID] ?? "the other side"
        ) { decision in
            guard let scorekeeper else { return }
            try? EngineBridge.appendPress(
                decision, hole: offer.hole, playerID: offer.trailingPlayerID, to: round,
                enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
                in: modelContext
            )
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
        } onClear: { kind in
            guard let scorekeeper else { return }
            try? EngineBridge.clearHoleEvent(
                kind, hole: hole, to: round,
                enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
                in: modelContext
            )
        }
    }
}

/// The Wolf declaration prompt on its own — who this hole's Wolf is partnering with, or going
/// alone. `GroupScoreEntry` shows it inline before scores unlock; `HoleScreenView` reopens the
/// same prompt standalone in a sheet when the header's wolf line is tapped, so both reuse this
/// rather than each keeping their own copy of the declaration logic.
struct WolfDeclarationPrompt: View {
    @Environment(\.modelContext) private var modelContext

    let round: RoundRecord
    let hole: Int
    let state: RoundState

    private var scorekeeper: SeatRecord? { round.orderedSeats.first }

    var body: some View {
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
}
