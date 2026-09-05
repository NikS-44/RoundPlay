import SwiftUI
import SwiftData
import UIKit
import RoundPlayEngine
import RoundPlayData

/// The Rounds tab: start a round, or resume one in progress.
struct RoundsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoundRecord.startedAt, order: .reverse) private var rounds: [RoundRecord]
    @Query private var courses: [CourseRecord]

    @State private var isCreatingRound = false
    @State private var activeRound: RoundRecord?
    @State private var newRoundStartingCourse: CourseRecord?
    @State private var playAgainSource: RoundRecord?
    @State private var isShowingRecentlyDeleted = false

    /// External trigger (from onboarding's "Start a Round"): a favorite course to preselect, and
    /// a signal to open the new-round sheet. Both default to no-ops so every other call site and
    /// every preview is unaffected.
    var autoStartFavorite: Binding<OpenGolfCourse?> = .constant(nil)
    var autoStartRound: Binding<Bool> = .constant(false)

    private func course(for round: RoundRecord) -> Course? {
        courses.first { $0.id == round.courseID }?.engineCourse
    }

    private func courseRecord(for round: RoundRecord) -> CourseRecord? {
        courses.first { $0.id == round.courseID }
    }

    private var inProgress: [RoundRecord] { rounds.filter { !$0.isComplete && !$0.isDeleted } }
    private var earlier: [RoundRecord] { rounds.filter { $0.isComplete && !$0.isDeleted } }

    /// "Delete" is a soft delete — the round moves to Recently Deleted, where it can be restored
    /// or purged for good. Nothing calls `modelContext.delete(_:)` on a round outside that screen.
    private func delete(_ round: RoundRecord) {
        if activeRound?.id == round.id { activeRound = nil }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            round.deletedAt = Date()
            try? modelContext.save()
        }
    }

    /// Height the current-round slot holds open whichever state is in it, so swapping a card for the
    /// empty state moves nothing below. Comfortably clears both: an in-progress card runs ~265pt,
    /// ~293pt when a long course name wraps to two lines, and the empty state ~235pt. Both are
    /// centred in it.
    private let slotHeight: CGFloat = 300

    /// The top of the screen: whatever is in progress, or the invitation to start something.
    ///
    /// One fixed-height box holding both states, which is what keeps this stable. As separate list
    /// rows, deleting the last in-progress round was a row delete plus a row insert that the List
    /// played in sequence — the card collapsed (yanking Previous Rounds up) and only then did the
    /// empty state expand and push it back down. A single row of a known height has nothing to diff
    /// and nothing to resize, so the swap is a content change in place.
    ///
    /// The cost is that swipe-to-delete belongs to the row rather than to a card, so the slot
    /// carries the swipe for the round it holds. A second round open at the same time is rare, and
    /// it gets an ordinary row of its own below the slot (see `body`) with its own swipe — one
    /// swipe shared by every card on screen would have no way to say which round it meant.
    private var isEmpty: Bool { inProgress.isEmpty }

    /// The round the slot holds: the first one in progress, if any. A collection rather than an
    /// optional so the `ForEach` inside the slot is never itself inserted or removed.
    private var slotRounds: [RoundRecord] { Array(inProgress.prefix(1)) }

    /// Rounds in progress past the first, which sit in ordinary rows under the slot.
    private var extraInProgress: [RoundRecord] { Array(inProgress.dropFirst()) }

    /// One in-progress round, as the card you tap to pick it back up.
    @ViewBuilder
    private func inProgressCard(_ round: RoundRecord, course: Course) -> some View {
        Button {
            activeRound = round
        } label: {
            InProgressRoundCard(round: round, course: course)
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        // The preview has to be spelled out. A `contextMenu` without one lifts the whole row, and
        // the slot's row is a 300pt box that holds the empty state too — so long-pressing the card
        // raised a white slab of the surrounding padding along with it. Naming the card as the
        // preview scopes the lift to the card that was pressed.
        .contextMenu {
            Button(role: .destructive) {
                delete(round)
            } label: {
                Label("Delete Round", systemImage: "trash")
            }
        } preview: {
            InProgressRoundCard(round: round, course: course)
        }
    }

    @ViewBuilder
    private var currentSlot: some View {
        // Both states are always in the tree, and only their opacity changes. An `if/else` here
        // still inserts and removes views, which tears the row's subtree down and rebuilds it — and
        // a List that is scrolled re-anchors when that happens, throwing the content up and then
        // settling it somewhere else. Nothing is ever inserted or removed now, so there is no
        // rebuild to re-anchor on.
        ZStack {
            StartRoundEmptyState(hasPreviousRounds: !earlier.isEmpty) { isCreatingRound = true }
                .opacity(isEmpty ? 1 : 0)
                .allowsHitTesting(isEmpty)

            VStack(spacing: 0) {
                ForEach(slotRounds) { round in
                    if let course = course(for: round) {
                        inProgressCard(round, course: course)
                    }
                }
            }
            .opacity(isEmpty ? 0 : 1)
            .allowsHitTesting(!isEmpty)
        }
        // A hard cut, not a crossfade. The swipe-to-delete gesture runs its own animated
        // transaction and the slot inherited it, so for a few frames both states were drawn at
        // partial opacity and "Nothing in progress" sat on top of the near-black card.
        .transaction { $0.animation = nil }
        // A floor rather than a fixed height, and only while the slot is the whole story. The empty
        // state and a single card both come in under it, so both render at exactly `slotHeight` and
        // swapping one for the other moves nothing. With a second card below, that same floor pads
        // ~40pt of dead space around the first one and reads as a gap between two cards that belong
        // to the same stack — and the empty state cannot appear while a round is in progress, so
        // there is nothing left to hold the box open for.
        .frame(minHeight: extraInProgress.isEmpty ? slotHeight : 0)
        .frame(maxWidth: .infinity)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let round = slotRounds.first {
                // Deliberately not `role: .destructive`. That role makes the List remove the row
                // itself: it collapsed this 300pt row to nothing (throwing a scrolled list up ~83pt)
                // and then re-inserted it once the state change produced a row again, which is the
                // up-then-down jump. The row is never actually going away — only its contents
                // change — so it must not be announced as a deletion. `.tint(.red)` keeps the
                // destructive look.
                Button {
                    delete(round)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    var body: some View {
        RoundPlayList.plain {
            currentSlot
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            // Rounds past the first are plain rows, which is the only way each card gets a swipe
            // of its own: `swipeActions` belongs to a row, so cards stacked inside one row can
            // only ever share a single swipe.
            ForEach(extraInProgress) { round in
                if let course = course(for: round) {
                    inProgressCard(round, course: course)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        // Destructive here, unlike the slot: this row really is going away, so
                        // the List should animate it out.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(round)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                }
            }

            if !earlier.isEmpty {
                Section {
                    ForEach(earlier) { round in
                        VStack(spacing: 8) {
                            roundLink(round) {
                                EarlierRoundRow(round: round, course: course(for: round))
                            }

                            HStack {
                                // A capsule chip, not an underlined text link — underlines read as
                                // web chrome and made the busiest row on the home screen look
                                // unfinished next to everything else in the app.
                                Button {
                                    guard courseRecord(for: round) != nil else { return }
                                    playAgainSource = round
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Play Again")
                                            .font(RoundPlayFont.archivo(13, .semiBold))
                                    }
                                    .foregroundStyle(RoundPlayColors.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().strokeBorder(RoundPlayColors.accent.opacity(0.45), lineWidth: 1)
                                    )
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Spacer()
                            }
                        }
                        // A light card, deliberately *not* the near-black board used for a round
                        // in progress. Sharing that treatment would cost the one piece of
                        // hierarchy this screen actually needs — the live round has to be the
                        // thing your eye lands on when you open the app mid-round. What the card
                        // does buy is holding the round and its Play Again chip together; as bare
                        // rows they were two elements joined only by whitespace and a hairline.
                        .padding(14)
                        .themedCard(cornerRadius: 16, fill: .secondaryBackground)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(round)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                } header: {
                    RoundPlaySectionHeader("Previous Rounds")
                }
            }
        }
        // Without this the gap between the Start a Round CTA and "Previous Rounds" reads as a
        // rendering gap rather than a section break.
        .listSectionSpacing(.compact)
        .navigationTitle("Rounds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isShowingRecentlyDeleted = true
                    } label: {
                        Label("Recently Deleted", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Round", systemImage: "plus") { isCreatingRound = true }
            }
        }
        .sheet(isPresented: $isShowingRecentlyDeleted) {
            NavigationStack {
                RecentlyDeletedRoundsView()
            }
        }
        .fullScreenCover(isPresented: $isCreatingRound) {
            NewRoundFlowView(startingCourse: newRoundStartingCourse) { round in
                activeRound = round
                newRoundStartingCourse = nil
            }
        }
        .onChange(of: autoStartRound.wrappedValue) { _, shouldStart in
            guard shouldStart else { return }
            if let favorite = autoStartFavorite.wrappedValue {
                newRoundStartingCourse = courses.first { $0.openGolfID == favorite.id }
            }
            isCreatingRound = true
            autoStartRound.wrappedValue = false
            autoStartFavorite.wrappedValue = nil
        }
        .sheet(item: $playAgainSource) { round in
            if let record = courseRecord(for: round) {
                PlayAgainConfirmView(sourceRound: round, courseRecord: record, context: modelContext) { newRound in
                    activeRound = newRound
                }
            }
        }
        .navigationDestination(item: $activeRound) { round in
            if let course = course(for: round) {
                RoundTabsView(round: round, course: course)
            } else {
                ContentUnavailableView(
                    "Course unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The course for this round is missing or incomplete.")
                )
            }
        }
    }

    @ViewBuilder
    private func roundLink<Label: View>(_ round: RoundRecord, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            if let course = course(for: round) {
                RoundTabsView(round: round, course: course)
            } else {
                ContentUnavailableView(
                    "Course unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The course for this round is missing or incomplete.")
                )
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

/// The featured card for a round still being played: status, score-strip progress, and the
/// scorekeeper's net across every game.
private struct InProgressRoundCard: View {
    let round: RoundRecord
    let course: Course

    private var state: RoundState { EngineBridge.roundState(for: round, course: course) }
    private var holeRange: ClosedRange<Int> { round.holeSegment.holeRange }

    private var holesPlayed: Int {
        holeRange.last { state.isComplete(hole: $0) }.map { $0 - holeRange.lowerBound + 1 } ?? 0
    }

    private var gameNames: String {
        (round.games ?? [])
            .compactMap { $0.gameType.map { GameLibrary.metadata(for: $0).displayName } }
            .joined(separator: ", ")
    }

    /// Money games only — Stroke Play settles to nothing, so counting it would put a "+$0.00" on
    /// a round that has no money in it.
    private var moneySettlements: [Settlement] {
        EngineBridge.settlements(for: round, course: course).filter { $0.gameType != .strokePlay }
    }

    private var net: Decimal {
        guard let scorekeeper = round.orderedSeats.first else { return 0 }
        return moneySettlements.reduce(Decimal(0)) { $0 + $1.money(for: scorekeeper.playerID) }
    }

    /// "4 players · Skins · thru 7", minus whatever doesn't apply. Built from the parts that
    /// exist rather than interpolated with fixed separators — a round with no games was rendering
    /// "1 player ·  · thru 6", with an orphaned dot where the game name would have gone.
    private var subtitle: String {
        [pluralized(round.orderedSeats.count, "player"),
         gameNames.isEmpty ? nil : gameNames,
         "thru \(holesPlayed)"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RoundPlayTypography.eyebrow("In Progress")
                    .foregroundStyle(RoundPlayColors.pin)
                Spacer()
                // No money games, no money line. A round that is just a scorecard has nothing to
                // report here, and "+$0.00" reads as a result rather than as an absence.
                if !moneySettlements.isEmpty {
                    RoundPlayTypography.money(net.formatted(.currency(code: "USD").sign(strategy: .always())))
                        .foregroundStyle(net >= 0 ? RoundPlayColors.moneyPositiveOnBoard : RoundPlayColors.moneyNegativeOnBoard)
                }
            }

            RoundPlayTypography.title(round.courseName)
                .foregroundStyle(RoundPlayColors.paperOnBoard)

            Text(subtitle)
                .font(RoundPlayFont.archivo(13))
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))

            Text(round.startedAt, style: .date)
                .font(RoundPlayFont.archivo(13))
                .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.6))

            HoleProgressDots(holesPlayed: holesPlayed, totalHoles: holeRange.count)

            Divider().overlay(RoundPlayColors.paperOnBoard.opacity(0.15))

            HStack {
                RoundPlayTypography.body("Continue round")
                    .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RoundPlayColors.paperOnBoard.opacity(0.5))
            }
        }
        .padding(18)
        .boardCard(cornerRadius: 16)
        // Deliberately no outer margin here: the card ends where the board ends. Insetting it
        // from inside meant the long-press preview — which is this view and everything it
        // draws — came up as a card floating on a pale margin. The margin belongs to the
        // layout around the card, so the call site owns it.
    }
}

/// The empty state when nothing is in progress: one unmissable way to begin, rather than a lone
/// toolbar "+" a first-time user has no reason to notice.
///
/// One shape in both cases — badge, headline, a line of copy, button — because a returning user
/// staring at a bare headline and a button got noticeably less than a first-timer did, and the
/// screen looked unfinished for it. Only the wording changes: a first-timer is told what the app
/// does, someone with rounds behind them is told what happens next.
private struct StartRoundEmptyState: View {
    var hasPreviousRounds: Bool = false
    let onStart: () -> Void

    private var headline: String {
        hasPreviousRounds ? "Nothing in progress" : "Your first round starts here"
    }

    private var detail: String {
        hasPreviousRounds
            ? "Start a round and we'll keep score for the group, handicaps and all."
            : "Keep score for the whole group, handicaps applied automatically. Skins, Nassau, Wolf, and more."
    }

    var body: some View {
        VStack(spacing: 0) {
            // A tinted badge rather than a bare 44pt glyph. At that size the raw symbol was the
            // loudest thing on the screen and outweighed the button it was meant to lead into.
            Image(systemName: "flag.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(RoundPlayColors.accent)
                .frame(width: 48, height: 48)
                .background(Circle().fill(RoundPlayColors.accent.opacity(0.12)))
                .padding(.bottom, 14)

            RoundPlayTypography.headline(headline)
                .multilineTextAlignment(.center)

            RoundPlayTypography.caption(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                // Capped so the line breaks at its own sentence boundary rather than running the
                // width of a large iPhone and leaving a two-word orphan on the last line.
                .frame(maxWidth: 270)
                .padding(.top, 6)

            // Sized to its label, not to the screen. A full-width 50pt bar on an otherwise empty
            // screen reads as a form's submit button; a hugging control reads as an invitation.
            Button(action: onStart) {
                Text("Start a Round")
                    .font(RoundPlayFont.archivo(16, .semiBold))
                    .padding(.horizontal, 10)
            }
            .roundPlayPrimaryButtonStyle()
            .controlSize(.large)
            .tint(RoundPlayColors.accent)
            .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

/// A row of 18 dots, filled fairway-green up through the last completed hole.
private struct HoleProgressDots: View {
    let holesPlayed: Int
    let totalHoles: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...totalHoles, id: \.self) { hole in
                Capsule()
                    .fill(hole <= holesPlayed ? RoundPlayColors.moneyPositiveOnBoard : RoundPlayColors.paperOnBoard.opacity(0.15))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("\(holesPlayed) of \(totalHoles) holes scored")
    }
}

/// A finished round in the "Earlier" list: course, date, and the scorekeeper's net.
private struct EarlierRoundRow: View {
    let round: RoundRecord
    let course: Course?

    /// `nil` when this round had no money games at all — a friendly round shouldn't advertise a
    /// meaningless "+$0.00" in the same slot where a real result goes.
    private var net: Decimal? {
        guard let course, let scorekeeper = round.orderedSeats.first else { return nil }
        let moneyGames = EngineBridge.settlements(for: round, course: course)
            .filter { $0.gameType != .strokePlay }
        guard !moneyGames.isEmpty else { return nil }
        return moneyGames.reduce(Decimal(0)) { $0 + $1.money(for: scorekeeper.playerID) }
    }

    private var playerNames: String {
        round.orderedSeats.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                RoundPlayTypography.headline(round.courseName)
                Text(playerNames)
                    .font(RoundPlayFont.archivo(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(round.startedAt, format: .dateTime.month(.abbreviated).day())
                    .font(RoundPlayFont.archivo(13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let net {
                RoundPlayTypography.money(net.formatted(.currency(code: "USD").sign(strategy: .always())))
                    .foregroundStyle(net > 0 ? RoundPlayColors.moneyPositive : net < 0 ? RoundPlayColors.moneyNegative : RoundPlayColors.moneyEven)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Scoring and standings for a round in progress.
///
/// Pushed from the Rounds tab, so without hiding the root tab bar here, its own Scorecard/
/// Standings bar would stack on top of the root Rounds/Games/Players bar and the root bar would
/// cover the bottom of whichever tab's content is showing.
struct RoundTabsView: View {
    let round: RoundRecord
    let course: Course

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum RoundTab: Hashable { case summary, hole, scorecard, standings }
    @State private var selection: RoundTab
    /// The hole `HoleScreenView` is showing, reported up via `CurrentHolePreferenceKey` so the
    /// nav-bar title — which this view draws, not `HoleScreenView` — can read "Hole 7" and be the
    /// tap target that opens the jump sheet.
    @State private var currentHole = 1
    @State private var isJumpingToHole = false
    @State private var isEditingRound = false
    @State private var isEditingScores = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingFinishEarly = false
    @State private var isShowingRoundOptions = false
    @State private var isSharingScorecard = false
    @State private var isSharingSettlement = false
    /// Generated as soon as the finished scorecard appears, not when Share is tapped — so there's
    /// no wait for the share sheet to have something to show.
    @State private var scorecardShareImage: UIImage?

    /// A finished round lands on Summary every time it's reopened; a round still being played
    /// always resumes on the Scorecard, mid-hole.
    init(round: RoundRecord, course: Course) {
        self.round = round
        self.course = course
        // A round in progress opens on Hole, because the reason you opened it is to enter a score.
        // The Scorecard tab is the landscape grid now, and landing there would rotate the phone
        // before you had asked for anything.
        _selection = State(initialValue: round.isComplete ? .summary : .hole)
    }

    private var hasGames: Bool { !(round.games ?? []).isEmpty }

    private var shareItems: [Any] {
        var items: [Any] = [RoundShareContent.settlementSummaryText(round: round, course: course)]
        // Falls back to rendering right now if the pre-generated one isn't there. `.task` warms
        // this up so the sheet opens instantly, but the cached `@State` does not reliably survive
        // until the sheet is built — SwiftUI was discarding it between the round appearing and
        // Share being tapped, and the round shared as text with no picture at all. Rendering the
        // card takes a few milliseconds, so the fallback is not worth avoiding.
        if let image = scorecardShareImage ?? RoundShareContent.scorecardImage(round: round, course: course) {
            items.insert(image, at: 0)
        }
        return items
    }

    /// The live Scorecard tab sits directly under `HoleHeader`'s near-black board background —
    /// the nav bar needs light text/icons there, same as the rest of the app's default dark-on-
    /// light everywhere else (the finished scorecard, Summary, Standings).
    private var showsDarkNavBar: Bool {
        !round.isComplete && selection == .hole
    }

    private var navigationTitleText: String {
        switch selection {
        case .summary: "Summary"
        case .hole: "Hole"
        case .scorecard: "Scorecard"
        case .standings: "Standings"
        }
    }

    var body: some View {
        // One NavigationStack for the whole tab view, not one per tab — RoundTabsView is itself
        // pushed from RoundsHomeView's stack, and nesting a fresh NavigationStack inside each tab
        // left the outer stack owning the visible bar while every tab's own navigationTitle/
        // toolbar silently never rendered (only the outer stack's bare back button showed). The
        // "Round Options" menu lives here — the shallowest point in this single stack — rather
        // than nested inside a tab's content, for the same reason.
        NavigationStack {
            TabView(selection: $selection) {
                if round.isComplete {
                    Tab("Summary", systemImage: "checkmark.seal", value: RoundTab.summary) {
                        RoundSummaryView(
                            round: round,
                            course: course,
                            onShare: { isSharingScorecard = true },
                            onSettleUp: { isSharingSettlement = true },
                            onShowScorecard: { selection = .scorecard },
                            onShowStandings: { selection = .standings }
                        )
                    }
                }
                if !round.isComplete {
                    Tab("Hole", systemImage: "flag.fill", value: RoundTab.hole) {
                        HoleScreenView(
                            round: round,
                            course: course,
                            isJumpingToHole: $isJumpingToHole
                        ) { selection = .summary }
                    }
                }
                Tab("Scorecard", systemImage: "square.grid.3x3", value: RoundTab.scorecard) {
                    FullScreenScorecardView(
                        round: round,
                        course: course,
                        focusHole: EngineBridge.roundState(for: round, course: course)
                            .currentHole(in: round.holeSegment)
                    )
                }
                // Solo standings would be a single stroke-play row, and its one useful number —
                // your score against par — is already in the hole header while you play and in
                // the summary once you finish.
                if !round.isSolo {
                    Tab("Standings", systemImage: "chart.bar", value: RoundTab.standings) {
                        RoundDashboardView(round: round, course: course)
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .onPreferenceChange(CurrentHolePreferenceKey.self) { hole in
                if let hole { currentHole = hole }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarColorScheme(showsDarkNavBar ? .dark : nil, for: .navigationBar)
            // The scorecard is the one landscape screen in a portrait-only app. Rotation is driven
            // from `selection` rather than the card's own onAppear/onDisappear because SwiftUI does
            // not guarantee onDisappear fires when a tab is deselected, and a missed call would
            // strand the whole app in landscape. Selection is state we own and can observe.
            .onChange(of: selection, initial: true) { _, tab in
                if tab == .scorecard {
                    OrientationLock.shared.requestLandscape()
                } else {
                    OrientationLock.shared.requestPortrait()
                }
            }
            // Leaving the round from the scorecard must hand portrait back too.
            .onDisappear { OrientationLock.shared.requestPortrait() }
            // A solo round has no Standings tab. Finishing while it happened to be selected would
            // otherwise strand `selection` on a tab that no longer exists in the TabView.
            .onChange(of: round.isComplete) {
                if round.isSolo && selection == .standings {
                    selection = round.isComplete ? .summary : .hole
                }
            }
            // The nav bar costs vertical space, which is the scarce dimension in landscape, and
            // the tab already names the screen.
            .toolbar(selection == .scorecard ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                // "Hole X" is the nav-bar title on the live round, and tapping it is how you jump
                // to another hole — the entry point a golfer reaches for first. The other tabs
                // fall back to `navigationTitleText`.
                if selection == .hole {
                    ToolbarItem(placement: .principal) {
                        Button {
                            isJumpingToHole = true
                        } label: {
                            // The chevron is a real, in-layout sibling of the text, not a
                            // zero-width overlay — a `.principal` item centers its own full
                            // bounding box in the nav bar, so leaving the chevron out of layout
                            // centered "Hole X" alone and let the chevron hang unbalanced off its
                            // trailing edge, reading as off-center against anything (like the
                            // solo score) that's centered on the bar's true middle. Including it
                            // centers the whole "Hole X ⌄" cluster instead.
                            HStack(spacing: 4) {
                                Text("Hole \(currentHole)")
                                    .font(RoundPlayFont.archivo(22, .bold))
                                    .contentTransition(.numericText())
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                        .tint(.primary)
                    }
                }
                // A generic "<" back button reads like undo or "go to the previous step" — this
                // isn't a step in a flow, it's leaving the round entirely, so it gets an explicit
                // exit affordance instead.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Exit Round", systemImage: "xmark")
                    }
                }
                if round.isComplete {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isSharingScorecard = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingRoundOptions = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .task(id: "\(round.isComplete)-\(round.nextSequence)") {
                guard round.isComplete, scorecardShareImage == nil else { return }
                scorecardShareImage = RoundShareContent.scorecardImage(round: round, course: course)
            }
            .sheet(isPresented: $isEditingRound) {
                RoundEditSheet(round: round, course: course)
            }
            .sheet(isPresented: $isEditingScores) {
                NavigationStack {
                    HoleScreenView(
                        round: round,
                        course: course,
                        isPostCompletionEdit: true,
                        isJumpingToHole: $isJumpingToHole
                    ) {
                        isEditingScores = false
                    }
                }
            }
            .sheet(isPresented: $isSharingScorecard) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $isSharingSettlement) {
                SettleUpSheet(round: round, course: course)
            }
            .confirmationDialog("Round Options", isPresented: $isShowingRoundOptions, titleVisibility: .visible) {
                if round.isComplete {
                    Button("Correct Scores") {
                        isEditingScores = true
                    }
                }
                Button("Edit Round") {
                    isEditingRound = true
                }
                if !round.isComplete {
                    if hasGames {
                        // Opens the breakdown directly. This used to just switch to Standings,
                        // which was where the disabled "Coming soon" stub lived.
                        Button("Settle Up") {
                            isSharingSettlement = true
                        }
                    }
                    Button("Finish Early") {
                        isConfirmingFinishEarly = true
                    }
                }
                Button("Delete Round", role: .destructive) {
                    isConfirmingDelete = true
                }
                Button("Cancel", role: .cancel) {}
            }
            // Destructive, and an alert for the same reason Delete is: a yes/no question about an
            // action that cannot be taken back. Nothing in the app ever clears `completedAt`, so
            // finishing is one-way, and the message has to say so rather than only describing what
            // happens to the unscored holes.
            .alert("Finish this round now?", isPresented: $isConfirmingFinishEarly) {
                Button("Finish Early", role: .destructive) {
                    round.completedAt = Date()
                    try? modelContext.save()
                    selection = .summary
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Holes without a score for every player will be left blank, and standings only count what's been entered. A finished round can't be reopened.")
            }
            // An alert, not a confirmation dialog. The other dialogs on this screen offer a choice
            // between several actions, which is what an action sheet is for; this one asks a yes/no
            // question about destroying something, which is what an alert is for. An alert also
            // lands in the middle of the screen rather than under the thumb that just tapped
            // Delete, so it is harder to confirm by accident.
            .alert("Delete this round?", isPresented: $isConfirmingDelete) {
                Button("Delete Round", role: .destructive) {
                    round.deletedAt = Date()
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This moves the round to Recently Deleted, where it can be restored.")
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { RoundsHomeView() }
        .modelContainer(PreviewData.container)
        .environment(RoundSyncSession.shared)
}

#Preview("Dark") {
    NavigationStack { RoundsHomeView() }
        .modelContainer(PreviewData.container)
        .environment(RoundSyncSession.shared)
        .preferredColorScheme(.dark)
}
