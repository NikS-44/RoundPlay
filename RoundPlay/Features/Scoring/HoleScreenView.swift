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

/// Lets `HoleScreenView` report the hole it's currently showing up to `RoundTabsView`, which
/// draws the nav-bar title for the live round.
struct CurrentHolePreferenceKey: PreferenceKey {
    static let defaultValue: Int? = nil
    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        if let next = nextValue() { value = next }
    }
}

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
    /// Owned by the enclosing `RoundTabsView` so the nav-bar title (which that view draws, not
    /// this one) can be the tap target that opens the jump sheet. Defaults to an inert binding
    /// for previews and any standalone use.
    @Binding private var isJumpingToHole: Bool
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
        isJumpingToHole: Binding<Bool> = .constant(false),
        onFinished: @escaping () -> Void = {}
    ) {
        self.round = round
        self.course = course
        self.isPostCompletionEdit = isPostCompletionEdit
        self._isJumpingToHole = isJumpingToHole
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

    /// The solo round's running score for the board's centre slot. Gross, not net: the number you
    /// glance at while playing should be the number on the card.
    private var runningScoreLine: (value: String, caption: String)? {
        guard round.isSolo, let seat = round.orderedSeats.first else { return nil }
        let played = RelativeToPar.holesPlayed(state: state, playerID: seat.playerID, holes: holeRange)
        guard played > 0 else { return nil }
        let versusPar = RelativeToPar.grossVersusPar(
            state: state, course: course, playerID: seat.playerID, holes: holeRange
        )
        return (RelativeToPar.label(versusPar), "Thru \(played)")
    }

    var body: some View {
        VStack(spacing: 0) {
            HoleHeader(
                par: course.hole(hole)?.par ?? 4,
                strokeIndex: course.hole(hole)?.strokeIndex ?? 1,
                centerLine: runningScoreLine,
                leaderLine: leaderLine,
                wolfLine: wolfLine,
                onTapWolf: { isEditingWolf = true }
            )

            if showsIncompleteWarning && !isHoleComplete(hole) {
                IncompleteHoleBanner(needsHoleEvents: requiredInputs.contains(.holeEvents))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollViewReader { scrollProxy in
            ScrollView {
                Group {
                    if round.isSolo, let seat = round.orderedSeats.first {
                        SoloScoreEntry(
                            seat: seat,
                            course: course,
                            hole: hole,
                            state: state,
                            onRecord: { record(strokes: $0, for: seat) }
                        )
                    } else {
                        GroupScoreEntry(
                            round: round,
                            course: course,
                            hole: hole,
                            state: state,
                            requiredInputs: requiredInputs,
                            isPostCompletionEdit: isPostCompletionEdit,
                            groupCenterScore: groupExpectedScore,
                            onRecord: { strokes, seat in record(strokes: strokes, for: seat) },
                            onClear: { seat in clearScore(for: seat) }
                        )
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
                showsEnteredCount: !round.isSolo,
                onPrevious: goToPreviousHole,
                onNext: goToNextHole,
                onFinish: finish
            )
        }
        .navigationTitle(isPostCompletionEdit ? "Correct Scores" : round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        // `RoundTabsView` owns the visible nav bar for the live round and draws "Hole X" as its
        // title; this hands that view the current hole so the title can track paging.
        .preference(key: CurrentHolePreferenceKey.self, value: hole)
        .toolbar {
            // The live round's nav bar is drawn by `RoundTabsView`; here (the "Correct Scores"
            // sheet, its own NavigationStack) this view still owns the bar, so it draws the same
            // tappable "Hole X" title for jumping between holes to fix scores.
            if isPostCompletionEdit {
                ToolbarItem(placement: .principal) {
                    Button {
                        isJumpingToHole = true
                    } label: {
                        // Only the text takes part in layout so the principal item centres on
                        // "Hole X"; the chevron is an overlay just off the trailing edge.
                        Text("Hole \(hole)")
                            .font(RoundPlayFont.archivo(22, .bold))
                            .contentTransition(.numericText())
                            .overlay(alignment: .trailing) {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 13, weight: .bold))
                                    .offset(x: 22)
                            }
                    }
                    .tint(.primary)
                }
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
                    WolfDeclarationPrompt(round: round, hole: hole, state: state)
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
