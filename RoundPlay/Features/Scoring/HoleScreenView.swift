import SwiftUI
import SwiftData
import UIKit
import RoundPlayEngine
import RoundPlayData

/// One hole, one screen — the paper scorecard.
///
/// Prompts are driven entirely by the union of `requiredInputs` across the round's active games.
/// This view has no idea what Wolf or Bingo Bango Bongo *are*; it knows that some game needs a
/// partner choice, or three hole events, and renders accordingly.
struct HoleScreenView: View {
    @Environment(\.modelContext) private var modelContext

    let round: RoundRecord
    let course: Course
    let isPostCompletionEdit: Bool
    /// Called once the round is confirmed complete — `RoundTabsView` uses this to flip to Standings.
    var onFinished: () -> Void = {}

    @State private var hole: Int
    @State private var showsIncompleteWarning = false
    @State private var isFixingIncompleteHoles = false
    @State private var isJumpingToHole = false
    @State private var isEditingWolf = false
    @State private var lastScore: (hole: Int, playerID: UUID)?
    /// Bumped every time Finish Round is refused for missing scores. Only exists so the warning
    /// haptic fires once per *attempt* — keying it off `showsIncompleteWarning` would also buzz
    /// when the banner is dismissed.
    @State private var blockedFinishAttempts = 0

    init(
        round: RoundRecord,
        course: Course,
        isPostCompletionEdit: Bool = false,
        onFinished: @escaping () -> Void = {}
    ) {
        self.round = round
        self.course = course
        self.isPostCompletionEdit = isPostCompletionEdit
        self.onFinished = onFinished
        // Opening a round already in progress should land on the first hole still missing a
        // score (or a required hole-event tally), not hole 1 every time — otherwise resuming a
        // round late means paging past everything you've already entered just to find where you
        // left off. This duplicates `requiredInputs`/`isHoleComplete` in miniature because Swift
        // won't let init call instance methods before every stored property (including `_hole`)
        // has a value.
        let range = round.holeSegment.holeRange
        let engineState = EngineBridge.roundState(for: round, course: course)
        let needsHoleEvents = (round.games ?? []).contains { game in
            guard let type = game.gameType else { return false }
            return GameLibrary.metadata(for: type).requiredInputs.contains(.holeEvents)
        }
        func isComplete(_ h: Int) -> Bool {
            guard engineState.isComplete(hole: h) else { return false }
            guard needsHoleEvents else { return true }
            return HoleEventKind.allCases.allSatisfy { engineState.holeEventWinner(hole: h, kind: $0) != nil }
        }
        let startingHole = range.first { !isComplete($0) } ?? range.lowerBound
        _hole = State(initialValue: startingHole)
    }

    private var holeRange: ClosedRange<Int> { round.holeSegment.holeRange }

    private var state: RoundState {
        EngineBridge.roundState(for: round, course: course)
    }

    /// Everything that has to be filled in on a hole — one score per seat, plus a winner for
    /// each hole-event tally (first on green, closest to pin, first in) when a game requires
    /// them. Bingo Bango Bongo's three tallies are just as required as anyone's score, so they
    /// count toward "X of Y entered" and the incomplete-hole warning the same way scores do.
    private func requiredEntryCount(for hole: Int) -> Int {
        round.orderedSeats.count + (requiredInputs.contains(.holeEvents) ? HoleEventKind.allCases.count : 0)
    }

    private func enteredEntryCount(for hole: Int) -> Int {
        let scores = round.orderedSeats.count { state.gross(hole: hole, player: $0.playerID) != nil }
        guard requiredInputs.contains(.holeEvents) else { return scores }
        let events = HoleEventKind.allCases.count { state.holeEventWinner(hole: hole, kind: $0) != nil }
        return scores + events
    }

    private func isHoleComplete(_ hole: Int) -> Bool {
        enteredEntryCount(for: hole) == requiredEntryCount(for: hole)
    }

    /// The first hole in this round's segment still missing a score or a required hole-event
    /// tally, if any.
    private var firstIncompleteHole: Int? {
        holeRange.first { !isHoleComplete($0) }
    }

    /// Every hole in this segment still incomplete — once Finish Round has failed once,
    /// Previous/Next only step through these instead of every hole in the round.
    private var incompleteHoles: [Int] {
        holeRange.filter { !isHoleComplete($0) }
    }

    private var previousNavigationHole: Int? {
        if isFixingIncompleteHoles {
            return incompleteHoles.last(where: { $0 < hole })
        }
        return hole > holeRange.lowerBound ? hole - 1 : nil
    }

    private var requiredInputs: Set<InputKind> {
        (round.games ?? []).reduce(into: Set<InputKind>()) { partial, game in
            guard let type = game.gameType else { return }
            partial.formUnion(GameLibrary.metadata(for: type).requiredInputs)
        }
    }

    private var wolfDeclarationPending: Bool {
        requiredInputs.contains(.partnerChoice) && state.wolfDeclaration(hole: hole) == nil
    }

    /// The score every carousel opens centered on — the same value for every player, so the
    /// strips line up column by column instead of each drifting to its own net par. This is the
    /// hole's par adjusted by the group's *average* handicap stroke, rounded to the nearest whole
    /// stroke, not each player's individual stroke — a high-handicapper's carousel shouldn't sit
    /// two positions to the right of a scratch player's on the same hole.
    private var groupExpectedScore: Int {
        let par = course.hole(hole)?.par ?? 4
        let seats = round.orderedSeats
        guard !seats.isEmpty else { return par }
        let totalStrokes = seats.reduce(0) { $0 + state.strokesReceived(hole: hole, player: $1.playerID) }
        let averageStrokes = (Double(totalStrokes) / Double(seats.count)).rounded()
        return par + Int(averageStrokes)
    }

    /// Whoever is entering scores. Phase 1 is single-device, so this is always the first seat;
    /// Phase 2 replaces it with the signed-in account.
    private var scorekeeper: SeatRecord? { round.orderedSeats.first }

    var body: some View {
        VStack(spacing: 0) {
            HoleHeader(
                hole: hole,
                par: course.hole(hole)?.par ?? 4,
                strokeIndex: course.hole(hole)?.strokeIndex ?? 1,
                leaderLine: leaderLine,
                wolfLine: wolfLine,
                onTapHole: { isJumpingToHole = true },
                onTapWolf: { isEditingWolf = true }
            )

            if showsIncompleteWarning && !isHoleComplete(hole) {
                IncompleteHoleBanner(needsHoleEvents: requiredInputs.contains(.holeEvents))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Above the scores because it is a question about the hole nobody has played
                    // yet, and because money agreed after the fact isn't agreed at all. It does
                    // not gate the strips the way the Wolf's declaration does — a group that
                    // would rather just play on can score straight through it.
                    if let pressOffer { pressPrompt(pressOffer) }

                    // Wolf declares before anyone's tee shot is scored — showing the score strips
                    // first would let the group enter scores while the Wolf is still deciding
                    // whether to go it alone, which the real game never allows. Once declared, the
                    // choice moves up into the header and this prompt gets out of the way.
                    if wolfDeclarationPending {
                        wolfPrompt
                    } else {
                        ForEach(round.orderedSeats) { seat in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    RoundPlayTypography.headline(seat.name)
                                    // Best Ball's team is fixed for the round; Sixes' partner
                                    // changes every six holes, so it's looked up per hole instead.
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
                                        groupCenterScore: groupExpectedScore,
                                        selected: state.gross(hole: hole, player: seat.playerID)
                                    ) { strokes in
                                        record(strokes: strokes, for: seat)
                                    }
                                    // Rebuild per hole so the carousel re-centers on the new
                                    // hole's expected score. Without this the view identity is
                                    // just the seat, so `onAppear` never fires again and hole 2
                                    // opens still scrolled to wherever hole 1 was left.
                                    .id(hole)
                                    if isPostCompletionEdit, state.gross(hole: hole, player: seat.playerID) != nil {
                                        Button("Clear") { clearScore(for: seat) }
                                            .font(RoundPlayFont.archivo(12, .semiBold))
                                            .foregroundStyle(RoundPlayColors.scoreOverPar)
                                    }
                                }
                            }
                        }

                        if requiredInputs.contains(.holeEvents) { holeEventsPrompt }
                    }
                }
                .padding()
                .id("top")
            }
            .onChange(of: hole) {
                scrollProxy.scrollTo("top", anchor: .top)
                // Undo is scoped to the score you just entered. Carrying it across holes meant
                // tapping it on hole 5 silently wiped a score back on hole 3.
                lastScore = nil
            }
            }

            HoleNavigationBar(
                hole: hole,
                holeRange: holeRange,
                isComplete: isHoleComplete(hole),
                enteredCount: enteredEntryCount(for: hole),
                totalCount: requiredEntryCount(for: hole),
                isLastHole: isLastActionableHole,
                isPostCompletionEdit: isPostCompletionEdit,
                previousHoleIsIncomplete: previousNavigationHole.map { incompleteHoles.contains($0) } ?? false,
                onPrevious: goToPreviousHole,
                onNext: goToNextHole,
                onFinish: finish
            )
        }
        .navigationTitle(isPostCompletionEdit ? "Correct Scores" : round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPostCompletionEdit {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink("History") { AuditLogView(round: round) }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let lastScore {
                    Button("Undo", systemImage: "arrow.uturn.backward") { undo(lastScore) }
                }
            }
        }
        // Refusing to finish and actually finishing are the two moments in a round worth feeling
        // through a pocket — the phone is often already on its way back there when either lands.
        .sensoryFeedback(RoundPlayHaptics.warning, trigger: blockedFinishAttempts)
        .sensoryFeedback(RoundPlayHaptics.success, trigger: round.isComplete)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $isJumpingToHole) {
            HoleJumpSheet(hole: $hole, holeRange: holeRange, incompleteHoles: Set(incompleteHoles))
                .presentationDetents([.height(300)])
                .onDisappear {
                    showsIncompleteWarning = false
                    isFixingIncompleteHoles = false
                }
        }
        .sheet(isPresented: $isEditingWolf) {
            NavigationStack {
                RoundPlayList.plain {
                    wolfPrompt
                }
                .navigationTitle("Wolf")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isEditingWolf = false }
                    }
                }
            }
            .presentationDetents([.height(320)])
        }
    }

    /// Finishing requires every hole to have every player's score. If any hole is short, jump
    /// there, flag it, and switch Previous/Next into "only the holes that still need scores"
    /// mode — walking every complete hole again to find the gaps is exactly what this avoids.
    private func finish() {
        if isPostCompletionEdit {
            onFinished()
            return
        }
        if let incomplete = firstIncompleteHole {
            withAnimation(.easeOut(duration: 0.25)) {
                hole = incomplete
                showsIncompleteWarning = true
            }
            isFixingIncompleteHoles = true
            blockedFinishAttempts += 1
            return
        }
        isFixingIncompleteHoles = false
        round.completedAt = Date()
        try? modelContext.save()
        CelebrationCenter.shared.celebrate(completionWord)
        onFinished()
    }

    /// The word the fireworks land on. Keyed to the scorekeeper's own result because that's whose
    /// phone this is — a round where you took money off your friends shouldn't read the same as
    /// one where you paid out. One short word: the overlay renders it at 68pt.
    private var completionWord: String {
        guard let scorekeeper else { return "WRAPPED" }
        let net = EngineBridge.settlements(for: round, course: course)
            .filter { $0.gameType != .strokePlay }
            .reduce(Decimal(0)) { $0 + $1.money(for: scorekeeper.playerID) }
        if net > 0 { return "CASHED" }
        if net < 0 { return "SETTLED" }
        return "WRAPPED"
    }

    /// True once there's nothing left to fix but the hole on screen — the navigation bar shows
    /// "Finish Round" here the same way it does on the round's actual last hole.
    private var isLastActionableHole: Bool {
        if isPostCompletionEdit { return hole == holeRange.upperBound }
        if hole == holeRange.upperBound { return true }
        guard isFixingIncompleteHoles else { return false }
        return !incompleteHoles.contains { $0 > hole }
    }

    private func goToPreviousHole() {
        withAnimation(.easeOut(duration: 0.25)) {
            if isFixingIncompleteHoles, let target = incompleteHoles.last(where: { $0 < hole }) {
                hole = target
                showsIncompleteWarning = true
            } else {
                hole = max(holeRange.lowerBound, hole - 1)
                showsIncompleteWarning = false
                isFixingIncompleteHoles = false
            }
        }
    }

    private func goToNextHole() {
        if isFixingIncompleteHoles {
            if let target = incompleteHoles.first(where: { $0 > hole }) {
                withAnimation(.easeOut(duration: 0.25)) {
                    hole = target
                    showsIncompleteWarning = true
                }
            } else {
                // No incomplete hole left ahead — either this was the last gap (finish succeeds)
                // or an earlier one still needs a score (finish jumps back to it).
                finish()
            }
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                hole = min(holeRange.upperBound, hole + 1)
            }
        }
    }

    /// "Ann leads Skins" — the top standing in the round's first game, once anyone is ahead.
    private var leaderLine: String? {
        guard let settlement = EngineBridge.settlements(for: round, course: course).first,
              let leader = settlement.standings.max(by: { $0.money < $1.money }),
              leader.money > 0,
              let name = round.orderedSeats.first(where: { $0.playerID == leader.playerID })?.name
        else { return nil }
        return "\(name) leads \(GameLibrary.metadata(for: settlement.gameType).displayName)"
    }

    /// "Nik is the wolf, partnering with Ann" — replaces `leaderLine` in the header once this
    /// hole's Wolf has decided, so the choice stays visible (and editable) without occupying the
    /// scroll area it used to block.
    private var wolfLine: String? {
        guard let (wolfID, declaration) = state.wolfDeclaration(hole: hole),
              let wolfName = round.orderedSeats.first(where: { $0.playerID == wolfID })?.name
        else { return nil }
        switch declaration {
        case .partner(let partnerID):
            guard let partnerName = round.orderedSeats.first(where: { $0.playerID == partnerID })?.name
            else { return "\(wolfName) is the Wolf" }
            return "\(wolfName) is the wolf, partnering with \(partnerName)"
        case .lone:
            return "\(wolfName) is the wolf, going alone"
        }
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

    private func record(strokes: Int, for seat: SeatRecord) {
        guard let scorekeeper else { return }
        try? EngineBridge.appendStrokes(
            strokes, hole: hole, playerID: seat.playerID, to: round,
            enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
            in: modelContext
        )
        lastScore = (hole, seat.playerID)
    }

    private func undo(_ score: (hole: Int, playerID: UUID)) {
        guard let scorekeeper else { return }
        try? EngineBridge.clearStrokes(
            hole: score.hole, playerID: score.playerID, to: round,
            enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
            in: modelContext
        )
        lastScore = nil
    }

    private func clearScore(for seat: SeatRecord) {
        guard let scorekeeper else { return }
        try? EngineBridge.clearStrokes(
            hole: hole, playerID: seat.playerID, to: round,
            enteredBy: scorekeeper.playerID, enteredByName: scorekeeper.name,
            in: modelContext
        )
    }
}

/// Hole number, par, and handicap — the three facts a golfer checks on the tee. Par gets the
/// big, easy-to-read treatment on the left since it's the number a player is actually judging
/// their score against hole after hole; the current hole number is secondary context, so it
/// moves to the small trailing stack — still tappable to jump to another hole, just no longer
/// shouting the loudest on the tee.
private struct HoleHeader: View {
    let hole: Int
    let par: Int
    let strokeIndex: Int
    let leaderLine: String?
    let wolfLine: String?
    let onTapHole: () -> Void
    let onTapWolf: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(spacing: 2) {
                RoundPlayTypography.eyebrow("Par")
                    .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))
                Text("\(par)")
                    .font(RoundPlayFont.archivo(44, .black))
                    .tracking(-2.2)
                    .foregroundStyle(RoundPlayColors.paperOnBoard)
                    .contentTransition(.numericText())
            }
            .frame(minWidth: 96)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(RoundPlayColors.paperOnBoard.opacity(0.35), lineWidth: 1.5)
            )

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

            VStack(alignment: .trailing, spacing: 6) {
                Button(action: onTapHole) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.5))
                            RoundPlayTypography.eyebrow("Hole")
                                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.5))
                        }
                        RoundPlayTypography.numeral("\(hole)", size: 21)
                            .foregroundStyle(RoundPlayColors.paperOnBoard)
                            .contentTransition(.numericText())
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .trailing, spacing: 2) {
                    RoundPlayTypography.eyebrow("Handicap")
                        .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.5))
                    RoundPlayTypography.numeral("\(strokeIndex)", size: 21)
                        .foregroundStyle(RoundPlayColors.paperOnBoard)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundPlayColors.board)
    }
}

/// Jump straight to any hole — tapping the hole number is faster than eighteen taps of Next.
private struct HoleJumpSheet: View {
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
private struct IncompleteHoleBanner: View {
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

private struct HoleNavigationBar: View {
    let hole: Int
    let holeRange: ClosedRange<Int>
    let isComplete: Bool
    let enteredCount: Int
    /// Seats needing a score, plus any required hole-event tallies (Bingo Bango Bongo's three
    /// winners) — not just the player count, when a game needs more than a stroke per hole.
    let totalCount: Int
    let isLastHole: Bool
    let isPostCompletionEdit: Bool
    let previousHoleIsIncomplete: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                // Always present, just invisible when complete — reserving the space keeps the
                // count text from sliding sideways as the icon appears and disappears.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isComplete ? 0 : 1)
                Text("\(enteredCount) of \(totalCount) entered")
                    .font(RoundPlayFont.archivo(18, .bold))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 10) {
                Button(action: onPrevious) {
                    Label("Previous Hole", systemImage: previousHoleIsIncomplete ? "exclamationmark.triangle.fill" : "chevron.left")
                        .font(RoundPlayFont.archivo(18, .bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(RoundPlayColors.accent)
                .disabled(hole == holeRange.lowerBound)

                if isLastHole {
                    Button(action: onFinish) {
                        Label(
                            isPostCompletionEdit ? "Done" : "Finish Round",
                            systemImage: isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                            .font(RoundPlayFont.archivo(20, .bold))
                            .labelStyle(.trailingIcon)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .roundPlayPrimaryButtonStyle()
                    .tint(RoundPlayColors.accent)
                } else {
                    // The warning is a small icon swap, not a color change — a fully orange
                    // button for "you haven't finished this hole yet" reads like an error state,
                    // when it's just an ordinary, expected part of entering scores.
                    Button(action: onNext) {
                        Label("Next Hole", systemImage: isComplete ? "chevron.right" : "exclamationmark.triangle.fill")
                            .font(RoundPlayFont.archivo(20, .bold))
                            .labelStyle(.trailingIcon)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .roundPlayPrimaryButtonStyle()
                    .tint(RoundPlayColors.accent)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(RoundPlayColors.backgroundSecondaryGrouped)
    }
}

/// Icon-after-title layout — "Next ›" reads more like forward motion than the default icon-first.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            // A fixed-width slot for the icon — chevron and warning-triangle glyphs aren't the
            // same width, so without this the whole label visibly shifts sideways every time
            // completeness flips and the icon swaps.
            configuration.icon
                .frame(width: 20)
        }
    }
}

private extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
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
