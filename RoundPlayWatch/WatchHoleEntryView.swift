import SwiftUI
import SwiftData
import RoundPlayEngine
import RoundPlayData

/// One hole, on the wrist — the phone's hole screen, narrowed rather than reinvented.
///
/// Every player is on screen at once: a row each, name above their own score strip. There is no
/// "current player" and so no gesture for changing it — you scroll to whoever you want, which is
/// what the Digital Crown is for and what the phone already asks of you.
///
/// Everything that isn't a score lives on one pinned line: back, the hole number, forward, and par.
/// A watch has room for roughly two player rows, so a separate navigation bar at the foot was
/// costing a quarter of the screen to say what four glyphs can.
struct WatchHoleEntryView: View {
    @Environment(\.modelContext) private var modelContext
    let round: RoundRecord
    let course: Course

    @State private var hole: Int
    /// Bingo Bango Bongo's tallies are their own screen — they're answered once per hole rather
    /// than once per player, and there is no room for them beside four score strips.
    @State private var isEnteringHoleEvents = false
    /// The end-of-round review, reached from the last hole's forward arrow.
    @State private var isReviewing = false

    init(round: RoundRecord, course: Course) {
        self.round = round
        self.course = course
        let state = EngineBridge.roundState(for: round, course: course)
        _hole = State(initialValue: state.currentHole(in: round.holeSegment))
    }

    private var state: RoundState {
        EngineBridge.roundState(for: round, course: course)
    }

    private var seats: [SeatRecord] { round.orderedSeats }
    private var par: Int { course.hole(hole)?.par ?? 4 }
    private var holeRange: ClosedRange<Int> { round.holeSegment.holeRange }

    private var requiredInputs: Set<InputKind> {
        var inputs: Set<InputKind> = []
        for game in round.games ?? [] {
            guard let type = game.gameType else { continue }
            inputs.formUnion(GameLibrary.metadata(for: type).requiredInputs)
        }
        if inputs.isEmpty { inputs = [.strokes] }
        return inputs
    }

    private var steps: [HoleEntryStep] {
        HoleEntrySequence.steps(requiredInputs: requiredInputs)
    }

    /// Derived from what the round actually holds rather than from a step counter. Coming back to
    /// a hole to fix a score used to replay the Wolf prompt, because the counter restarted at zero
    /// while the declaration it was asking for had been made twenty minutes ago.
    private var currentStep: HoleEntryStep {
        if steps.contains(.partnerChoice), state.wolfDeclaration(hole: hole) == nil {
            return .partnerChoice
        }
        if isEnteringHoleEvents, steps.contains(.holeEvents) {
            return .holeEvents
        }
        return .scores
    }

    var body: some View {
        Group {
            switch currentStep {
            case .partnerChoice:
                WatchWolfStep(round: round, hole: hole)
            case .scores:
                scoresStep
            case .holeEvents:
                WatchHoleEventsStep(round: round, hole: hole, onConfirm: goToNextHole)
            }
        }
        // Everything that isn't a score lives in the bar alongside the clock — the strip of screen
        // every app is given, which this one was leaving blank once the course name came out of it.
        //
        // It is one toolbar item rather than a title plus a leading item, because watchOS stacks
        // those on separate rows: the arrows ended up above the hole number instead of flanking it.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { holeBar }
        }
        .onChange(of: hole) { isEnteringHoleEvents = false }
        .sheet(isPresented: $isReviewing) {
            NavigationStack {
                WatchRoundReviewView(round: round, course: course, hole: $hole)
            }
        }
    }

    // MARK: - Scores

    /// A plain `ScrollView`, deliberately not a `List`.
    ///
    /// Each player's strip is a horizontal scroller, and horizontal scrollers inside a watchOS
    /// `List` row recursed through the focus machinery until the view graph blew the stack —
    /// EXC_BAD_ACCESS, "excessive recursion", straight out of `_didChange(toFirstResponder:)`.
    /// A `ScrollView` carries none of that per-row focus apparatus and nests cleanly.
    private var scoresStep: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(seats) { seat in
                            seatRow(seat, proxy: proxy)
                                .id(seat.playerID)
                        }
                        nextHoleRow
                            .id(Self.nextRowID)

                        // Room below the last row so it can actually reach the top of the screen.
                        // Without it the scroll runs out and the Next button settles wherever the
                        // end of the list happens to fall — lower than the strips, which is the one
                        // place it must not be, since the whole point is that it arrives under the
                        // thumb that just tapped the last score.
                        Color.clear
                            .frame(height: 130)
                    }
                    .padding(.top, 4 - WatchLayout.toolbarLift)
                    .padding(.bottom, 6)
                }
                // Arriving at a hole lands on the first player who still needs a score, and on the
                // top of the card when everyone already has one.
                //
                // Without any reset the list kept the offset from the hole before, so walking to
                // the next tee opened on the last player with empty space under them, and the
                // people above — the ones actually needing scores — sat out of sight above the
                // fold. Resetting to the first *unscored* player goes further: on a hole you have
                // come back to fix, it puts the gap on screen instead of making you find it.
                .onChange(of: hole) {
                    guard let target = firstUnscoredSeat ?? seats.first else { return }
                    proxy.scrollTo(target.playerID, anchor: .top)
                }
            }
        }
    }

    /// An untouched hole is not a warning — it is a hole you have just walked onto, so it gets a
    /// plain statement of fact rather than an orange one.
    private var footerCaption: String {
        if isHoleComplete { return "All scored" }
        if hasPartialScores { return missingSummary }
        return "No scores yet"
    }

    /// Scroll target for the row below the last player.
    private static let nextRowID = "next-hole"

    /// The way on, at the foot of the card.
    ///
    /// Deliberately built like a seat row — a caption line above a 42pt-tall control — because the
    /// list scrolls it to the same place it scrolls each player. Score the last player and this
    /// lands under the thumb that just tapped, so a whole hole is tap, tap, tap, tap, on one spot.
    private var nextHoleRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            // What the hole is short of, said at the point where leaving it is the thing you are
            // about to do.
            //
            // This used to be a line above the scores, and it appeared the moment you entered the
            // first one — which pushed every strip down by its own height, so the second tap of a
            // hole landed where the first had been and hit nothing. A caption on a row that is
            // always present costs no layout at all.
            HStack(spacing: 4) {
                if hasPartialScores {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(footerCaption)
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(hasPartialScores ? WatchPalette.pin : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.leading, WatchLayout.leadingMargin)
            .padding(.trailing, 8)

            Button(action: advance) {
                HStack(spacing: 5) {
                    Text(isLastHole ? "Review round" : "Next hole")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: isLastHole ? "flag.checkered" : "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WatchPalette.accent)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.leading, WatchLayout.leadingMargin)
            .padding(.trailing, 8)
        }
    }

    /// Back and forward, in the navigation bar beside the hole number.
    ///
    /// Neither is ever disabled by an unfinished hole. Leaving a score for later is normal:
    /// somebody is still putting, somebody has walked on to the next tee. The incomplete state
    /// annotates the way out instead of barring it.
    private var holeBar: some View {
        HStack(spacing: 7) {
            // Carries the warning mark when the hole *behind* you is the one with the gap, so a
            // score you skipped stays visible from wherever you end up.
            Button(action: goToPreviousHole) {
                // The glyph stays a chevron and the colour carries the warning. Swapping in a
                // triangle put two identical triangles side by side in the bar, which said
                // "something is wrong" while destroying the only cue for which way is back.
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(previousHoleIsIncomplete ? WatchPalette.pin : .primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(hole == holeRange.lowerBound)
            .opacity(hole == holeRange.lowerBound ? 0.3 : 1)
            .accessibilityLabel(previousHoleIsIncomplete
                                ? "Previous hole, incomplete" : "Previous hole")

            Text("Hole \(hole)")
                .font(.headline)
                .lineLimit(1)
                .contentTransition(.numericText())

            Button(action: advance) {
                Image(systemName: isLastHole ? "flag.checkered" : "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hasPartialScores ? WatchPalette.pin : .primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(forwardAccessibilityLabel)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .offset(y: -WatchLayout.toolbarLift)
    }

    @ViewBuilder
    private func seatRow(_ seat: SeatRecord, proxy: ScrollViewProxy) -> some View {
        let strokes = state.strokesReceived(hole: hole, player: seat.playerID)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                // A solo round's one row doesn't need to be told whose it is.
                if seats.count > 1 {
                    Text(seat.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                // Says why this player's strip opens a chip further right than everyone else's.
                if strokes > 0 {
                    Text("+\(strokes)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WatchPalette.pin)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, WatchLayout.leadingMargin)

            WatchScoreStrip(
                par: par,
                strokesReceived: strokes,
                groupCenterScore: groupCenterScore,
                selected: state.gross(hole: hole, player: seat.playerID),
                onSelect: { record($0, for: seat, scrollingWith: proxy) }
            )
            // The hole decides where this strip belongs, so it belongs in the strip's identity —
            // without it, hole 4 opens still scrolled to wherever hole 3 was left.
            .id("\(hole)-\(seat.playerID)")
        }
    }

    // MARK: - Completeness

    /// Seats scored, plus Bingo Bango Bongo's tallies when a game needs them — "missing a score" is
    /// only half the story on those rounds, and sends the scorekeeper hunting for a score that is
    /// already there.
    private func enteredCount(for hole: Int) -> Int {
        var count = seats.filter { state.gross(hole: hole, player: $0.playerID) != nil }.count
        if requiredInputs.contains(.holeEvents) {
            count += HoleEventKind.allCases.filter { state.holeEventWinner(hole: hole, kind: $0) != nil }.count
        }
        return count
    }

    private var requiredCount: Int {
        seats.count + (requiredInputs.contains(.holeEvents) ? HoleEventKind.allCases.count : 0)
    }

    private var enteredCount: Int { enteredCount(for: hole) }

    private func isComplete(_ hole: Int) -> Bool { enteredCount(for: hole) >= requiredCount }

    private var isHoleComplete: Bool { isComplete(hole) }

    /// Some players scored, others not. This — and not an untouched hole — is the state worth
    /// warning about: it is the one where you are about to walk off leaving somebody out of a hole
    /// the rest of the group has finished.
    ///
    /// A hole nobody has scored yet is simply a hole you have just arrived at. Marking that in
    /// orange means every hole opens shouting about a mistake you have not had the chance to make,
    /// which teaches you to ignore the colour by about the fourth tee. If you do leave a hole
    /// untouched, the back arrow on the next one turns orange and the end-of-round review lists it.
    private var hasPartialScores: Bool { enteredCount > 0 && !isHoleComplete }

    private var previousHoleIsIncomplete: Bool {
        hole > holeRange.lowerBound && !isComplete(hole - 1)
    }

    private var isLastHole: Bool { hole == holeRange.upperBound }

    /// Par adjusted by the group's average handicap stroke on this hole — not each player's own.
    /// Every unscored strip opens here, which is what keeps the rows in a column.
    private var groupCenterScore: Int {
        guard !seats.isEmpty else { return par }
        let total = seats.reduce(0) { $0 + state.strokesReceived(hole: hole, player: $1.playerID) }
        return par + Int((Double(total) / Double(seats.count)).rounded())
    }

    /// What the hole is still short of — named when it's a person, counted when it isn't. "Ben and
    /// Cal to score" tells you who to ask; "2 of 4 entered" makes you work that out yourself.
    private var missingSummary: String {
        let unscored = seats.filter { state.gross(hole: hole, player: $0.playerID) == nil }
        let tallies = requiredInputs.contains(.holeEvents)
            ? HoleEventKind.allCases.filter { state.holeEventWinner(hole: hole, kind: $0) == nil }.count
            : 0
        if unscored.isEmpty {
            return tallies == 1 ? "1 tally left" : "\(tallies) tallies left"
        }
        let names = unscored.map(\.name)
        let who = names.count <= 2 ? names.joined(separator: " and ") : "\(names.count) players"
        return tallies > 0 ? "\(who), \(tallies) tallies" : "\(who) to score"
    }

    // MARK: - Actions

    private func record(_ strokes: Int, for seat: SeatRecord, scrollingWith proxy: ScrollViewProxy) {
        let keeper = seats.first
        try? EngineBridge.appendStrokes(
            strokes, hole: hole, playerID: seat.playerID, to: round,
            enteredBy: keeper?.playerID ?? seat.playerID,
            enteredByName: keeper?.name ?? seat.name,
            in: modelContext
        )

        // Only the last score in a hole moves the screen, and it moves it to the way out.
        //
        // Scrolling to the next player after every tap was too much: the next row is barely a
        // flick away, groups call their scores out in whatever order they finish rather than in
        // card order, and a screen that jumps under a thumb which is still moving reads as the app
        // twitching. The end of a hole is different — the button is genuinely far down the list,
        // and there is exactly one thing you want next.
        guard nextUnscoredSeat(after: seat) == nil, isHoleComplete else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.nextRowID, anchor: .top)
        }
    }

    /// The first player on this hole with no score. Nil once the hole is fully entered, which is
    /// what parks a finished hole at the top rather than somewhere in the middle.
    private var firstUnscoredSeat: SeatRecord? {
        seats.first { state.gross(hole: hole, player: $0.playerID) == nil }
    }

    private func nextUnscoredSeat(after seat: SeatRecord) -> SeatRecord? {
        guard let index = seats.firstIndex(where: { $0.playerID == seat.playerID }) else { return nil }
        return seats[(index + 1)...].first { state.gross(hole: hole, player: $0.playerID) == nil }
    }

    private var forwardAccessibilityLabel: String {
        if isLastHole { return "Review and finish round" }
        return hasPartialScores ? "Next hole, incomplete" : "Next hole"
    }

    private func advance() {
        if steps.contains(.holeEvents), !isEnteringHoleEvents {
            isEnteringHoleEvents = true
        } else if isLastHole {
            // The end of the round is a destination, not a dead end. This arrow used to be
            // disabled here, which left a round with no way to finish from the watch at all.
            isReviewing = true
        } else {
            goToNextHole()
        }
    }

    private func goToNextHole() {
        guard hole < holeRange.upperBound else { return }
        hole += 1
    }

    private func goToPreviousHole() {
        guard hole > holeRange.lowerBound else { return }
        hole -= 1
    }
}

/// Who this hole's Wolf is playing with. Gates the scores, the way it does on the phone — the real
/// game never lets anyone tee off while the Wolf is still deciding.
struct WatchWolfStep: View {
    @Environment(\.modelContext) private var modelContext
    let round: RoundRecord
    let hole: Int

    private var wolf: SeatRecord {
        let seats = round.orderedSeats
        return seats[(hole - 1) % max(1, seats.count)]
    }

    var body: some View {
        List {
            Text("\(wolf.name) is Wolf")
                .font(.headline)
            Button("Lone Wolf") { declare(.lone) }
            ForEach(round.orderedSeats.filter { $0.playerID != wolf.playerID }) { seat in
                Button("Partner \(seat.name)") { declare(.partner(seat.playerID)) }
            }
        }
    }

    private func declare(_ declaration: WolfDeclaration) {
        let keeper = round.orderedSeats.first
        try? EngineBridge.appendWolfDeclaration(
            declaration, hole: hole, wolfID: wolf.playerID, to: round,
            enteredBy: keeper?.playerID ?? wolf.playerID,
            enteredByName: keeper?.name ?? wolf.name,
            in: modelContext
        )
    }
}

struct WatchHoleEventsStep: View {
    @Environment(\.modelContext) private var modelContext
    let round: RoundRecord
    let hole: Int
    let onConfirm: () -> Void

    var body: some View {
        List {
            ForEach(HoleEventKind.allCases, id: \.self) { kind in
                Section(kind.rawValue.capitalized) {
                    ForEach(round.orderedSeats) { seat in
                        Button(seat.name) {
                            let keeper = round.orderedSeats.first
                            try? EngineBridge.appendHoleEvent(
                                kind, hole: hole, playerID: seat.playerID, to: round,
                                enteredBy: keeper?.playerID ?? seat.playerID,
                                enteredByName: keeper?.name ?? seat.name,
                                in: modelContext
                            )
                        }
                    }
                }
            }
            Button("Next hole") { onConfirm() }
        }
    }
}
